// Original PC2Coop code, MIT. Steam transport for live co-op inside the game process.
//
// Uses the game's own steam_api64.dll (already initialised by PC2): friends-only lobby,
// overlay invites, SteamNetworkingMessages (P2P with Valve relay, no port forwarding).
// Lua sends commands as one record (nibble channel), and polls events one string at a
// time. All Steam calls happen on the Lua thread; Steam callbacks arrive through the
// game's own SteamAPI_RunCallbacks and only queue events.
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <deque>
#include <string>
#include <vector>
#include <cctype>
#include <utility>

void pc2_diagnostic_event(const char*) noexcept;
int pc2_push_string(void* state, const char* text, size_t size) noexcept;

namespace {
using u64 = unsigned long long;
using SteamAPICall = u64;

// Layout of SteamNetworkingIdentity (steamnetworkingtypes.h): type, size, 128-byte union.
struct Identity { int type; int size; unsigned char data[128]; };
static_assert(sizeof(Identity) == 136, "SteamNetworkingIdentity size");

// Leading fields of SteamNetworkingMessage_t.
struct Message { void* data; int size; unsigned int connection; Identity peer; };

// Same declaration as steam_api's CCallbackBase, so MSVC builds the identical vtable.
class CallbackBase {
public:
    CallbackBase() : flags(0), id(0) {}
    virtual void Run(void* param) = 0;
    virtual void Run(void* param, bool ioFailure, SteamAPICall call) = 0;
    virtual int GetCallbackSizeBytes() = 0;
    unsigned char flags;
    int id;
};

struct Api {
    HMODULE dll = nullptr;
    void* (*Friends)() = nullptr;
    void* (*Matchmaking)() = nullptr;
    void* (*Messages)() = nullptr;
    void* (*Utils)() = nullptr;
    void* (*User)() = nullptr;
    void (*RegisterCallback)(CallbackBase*, int) = nullptr;
    void (*RegisterCallResult)(CallbackBase*, SteamAPICall) = nullptr;
    void (*UnregisterCallResult)(CallbackBase*, SteamAPICall) = nullptr;
    u64 (*GetSteamID)(void*) = nullptr;
    const char* (*GetPersonaName)(void*) = nullptr;
    const char* (*GetFriendPersonaName)(void*, u64) = nullptr;
    bool (*SetRichPresence)(void*, const char*, const char*) = nullptr;
    void (*ActivateInviteDialog)(void*, u64) = nullptr;
    SteamAPICall (*CreateLobby)(void*, int, int) = nullptr;
    SteamAPICall (*JoinLobby)(void*, u64) = nullptr;
    void (*LeaveLobby)(void*, u64) = nullptr;
    u64 (*GetLobbyOwner)(void*, u64) = nullptr;
    int (*GetNumLobbyMembers)(void*, u64) = nullptr;
    u64 (*GetLobbyMemberByIndex)(void*, u64, int) = nullptr;
    bool (*SetLobbyData)(void*, u64, const char*, const char*) = nullptr;
    int (*SendMessageToUser)(void*, const Identity*, const void*, unsigned int, int, int) = nullptr;
    int (*ReceiveMessages)(void*, int, Message**, int) = nullptr;
    bool (*AcceptSession)(void*, const Identity*) = nullptr;
    bool (*CloseSession)(void*, const Identity*) = nullptr;
    void (*ReleaseMessage)(Message*) = nullptr;
    void (*SetSteamID64)(Identity*, u64) = nullptr;
    u64 (*GetSteamID64)(const Identity*) = nullptr;
    void (*InitRelay)(void*) = nullptr;
    int (*GetFriendCount)(void*, int) = nullptr;
    u64 (*GetFriendByIndex)(void*, int, int) = nullptr;
    int (*GetFriendPersonaState)(void*, u64) = nullptr;
    bool (*GetFriendGamePlayed)(void*, u64, void*) = nullptr;
    bool (*InviteUserToGame)(void*, u64, const char*) = nullptr;
} api;

template <class T> bool bind(T& slot, const char* name) {
    slot = reinterpret_cast<T>(GetProcAddress(api.dll, name));
    return slot != nullptr;
}

SRWLOCK queue_lock = SRWLOCK_INIT;
std::deque<std::string> events;
bool ready = false;
bool failed = false;
u64 self_id = 0;
u64 lobby = 0;
std::vector<u64> members;
constexpr int kReliable = 8;      // k_nSteamNetworkingSend_Reliable
constexpr int kChannel = 0;
constexpr size_t kMaxQueued = 4096;

void queue(std::string event) {
    AcquireSRWLockExclusive(&queue_lock);
    if (events.size() < kMaxQueued) events.push_back(std::move(event));
    ReleaseSRWLockExclusive(&queue_lock);
}

std::string id_text(u64 id) { char b[32]; sprintf_s(b, "%llu", id); return b; }

std::string friend_name(u64 id) {
    const char* name = api.GetFriendPersonaName ? api.GetFriendPersonaName(api.Friends(), id) : nullptr;
    std::string clean;
    for (const char* p = name ? name : "?"; *p && clean.size() < 64; ++p)
        if (*p != '|' && *p != '\n' && *p != '\r') clean += *p;
    return clean.empty() ? "?" : clean;
}

Identity identity(u64 id) { Identity i{}; api.SetSteamID64(&i, id); return i; }

bool is_member(u64 id) {
    for (u64 m : members) if (m == id) return true;
    return false;
}

void refresh_members() {
    std::vector<u64> now;
    if (lobby) {
        int count = api.GetNumLobbyMembers(api.Matchmaking(), lobby);
        for (int i = 0; i < count && i < 64; ++i) now.push_back(api.GetLobbyMemberByIndex(api.Matchmaking(), lobby, i));
    }
    for (u64 id : now) {
        bool known = false;
        for (u64 m : members) known = known || m == id;
        if (!known && id != self_id) queue("member:join|" + id_text(id) + "|" + friend_name(id));
    }
    for (u64 id : members) {
        bool still = false;
        for (u64 m : now) still = still || m == id;
        if (!still && id != self_id) {
            queue("member:leave|" + id_text(id));
            Identity peer = identity(id);
            api.CloseSession(api.Messages(), &peer);
        }
    }
    members = now;
}

void entered(u64 id, bool ok) {
    if (!ok) { queue("lobby:error|enter-failed"); return; }
    lobby = id;
    u64 owner = api.GetLobbyOwner(api.Matchmaking(), lobby);
    std::string connect = "+connect_lobby " + id_text(lobby);
    api.SetRichPresence(api.Friends(), "connect", connect.c_str());
    api.SetRichPresence(api.Friends(), "status", "PC2 Co-op");
    members.clear();
    refresh_members();
    queue("lobby:entered|" + id_text(lobby) + "|" + id_text(owner) + "|" + friend_name(owner));
    // Open sessions in both directions; sending first auto-accepts on the peer's side.
    for (u64 m : members) {
        if (m == self_id) continue;
        Identity peer = identity(m);
        const char hello[] = "\x01hello";
        api.SendMessageToUser(api.Messages(), &peer, hello, sizeof(hello) - 1, kReliable, kChannel);
    }
}

// Callback structs (Steam packs callbacks to 8 bytes on Windows).
#pragma pack(push, 8)
struct LobbyCreated { int result; u64 lobby; };
struct LobbyEnter { u64 lobby; unsigned int permissions; bool locked; unsigned int response; };
struct LobbyChatUpdate { u64 lobby; u64 changed; u64 making; unsigned int state; };
struct LobbyJoinRequested { u64 lobby; u64 friend_id; };
struct SessionRequest { Identity remote; };
#pragma pack(pop)

template <class Data, int Id>
class Callback : public CallbackBase {
public:
    explicit Callback(void (*handler)(const Data&)) : handler_(handler) {}
    void Run(void* param) override { handler_(*static_cast<const Data*>(param)); }
    void Run(void* param, bool ioFailure, SteamAPICall) override { if (!ioFailure) handler_(*static_cast<const Data*>(param)); }
    int GetCallbackSizeBytes() override { return static_cast<int>(sizeof(Data)); }
    void Register() { api.RegisterCallback(this, Id); }
private:
    void (*handler_)(const Data&);
};

template <class Data, int Id>
class CallResult : public CallbackBase {
public:
    explicit CallResult(void (*handler)(const Data&, bool)) : handler_(handler) { id = Id; }
    void Set(SteamAPICall call) {
        if (call_) api.UnregisterCallResult(this, call_);
        call_ = call;
        if (call) api.RegisterCallResult(this, call);
    }
    void Run(void* param) override { call_ = 0; handler_(*static_cast<const Data*>(param), false); }
    void Run(void* param, bool ioFailure, SteamAPICall) override {
        call_ = 0;
        handler_(*static_cast<const Data*>(param), ioFailure);
    }
    int GetCallbackSizeBytes() override { return static_cast<int>(sizeof(Data)); }
private:
    void (*handler_)(const Data&, bool);
    SteamAPICall call_ = 0;
};

void on_created(const LobbyCreated& data, bool failure) {
    if (failure || data.result != 1) { queue("lobby:error|create-failed|" + std::to_string(data.result)); return; }
    api.SetLobbyData(api.Matchmaking(), data.lobby, "pc2coop", "1");
    queue("lobby:created|" + id_text(data.lobby));
}
void on_enter(const LobbyEnter& data) { entered(data.lobby, data.response == 1); }
void on_chat_update(const LobbyChatUpdate& data) { if (data.lobby == lobby) refresh_members(); }
void on_join_requested(const LobbyJoinRequested& data) {
    queue("invite:accepted|" + id_text(data.lobby) + "|" + id_text(data.friend_id) + "|" + friend_name(data.friend_id));
}
void on_session_request(const SessionRequest& data) {
    u64 id = api.GetSteamID64(&data.remote);
    // Only lobby members may open a session; refresh first, joins can race the request.
    refresh_members();
    if (is_member(id)) api.AcceptSession(api.Messages(), &data.remote);
    else queue("net:refused|" + id_text(id));
}

CallResult<LobbyCreated, 513>* created_result = nullptr;
CallResult<LobbyEnter, 504>* enter_result = nullptr;
void on_enter_result(const LobbyEnter& data, bool failure) { entered(data.lobby, !failure && data.response == 1); }

bool initialise() {
    if (ready || failed) return ready;
    api.dll = GetModuleHandleW(L"steam_api64.dll");
    bool ok = api.dll != nullptr;
    ok = ok && bind(api.Friends, "SteamAPI_SteamFriends_v017") && bind(api.Matchmaking, "SteamAPI_SteamMatchmaking_v009")
        && bind(api.Messages, "SteamAPI_SteamNetworkingMessages_SteamAPI_v002")
        && bind(api.Utils, "SteamAPI_SteamNetworkingUtils_SteamAPI_v004") && bind(api.User, "SteamAPI_SteamUser_v021")
        && bind(api.RegisterCallback, "SteamAPI_RegisterCallback") && bind(api.RegisterCallResult, "SteamAPI_RegisterCallResult")
        && bind(api.UnregisterCallResult, "SteamAPI_UnregisterCallResult")
        && bind(api.GetSteamID, "SteamAPI_ISteamUser_GetSteamID") && bind(api.GetPersonaName, "SteamAPI_ISteamFriends_GetPersonaName")
        && bind(api.GetFriendPersonaName, "SteamAPI_ISteamFriends_GetFriendPersonaName")
        && bind(api.SetRichPresence, "SteamAPI_ISteamFriends_SetRichPresence")
        && bind(api.ActivateInviteDialog, "SteamAPI_ISteamFriends_ActivateGameOverlayInviteDialog")
        && bind(api.CreateLobby, "SteamAPI_ISteamMatchmaking_CreateLobby") && bind(api.JoinLobby, "SteamAPI_ISteamMatchmaking_JoinLobby")
        && bind(api.LeaveLobby, "SteamAPI_ISteamMatchmaking_LeaveLobby") && bind(api.GetLobbyOwner, "SteamAPI_ISteamMatchmaking_GetLobbyOwner")
        && bind(api.GetNumLobbyMembers, "SteamAPI_ISteamMatchmaking_GetNumLobbyMembers")
        && bind(api.GetLobbyMemberByIndex, "SteamAPI_ISteamMatchmaking_GetLobbyMemberByIndex")
        && bind(api.SetLobbyData, "SteamAPI_ISteamMatchmaking_SetLobbyData")
        && bind(api.SendMessageToUser, "SteamAPI_ISteamNetworkingMessages_SendMessageToUser")
        && bind(api.ReceiveMessages, "SteamAPI_ISteamNetworkingMessages_ReceiveMessagesOnChannel")
        && bind(api.AcceptSession, "SteamAPI_ISteamNetworkingMessages_AcceptSessionWithUser")
        && bind(api.CloseSession, "SteamAPI_ISteamNetworkingMessages_CloseSessionWithUser")
        && bind(api.ReleaseMessage, "SteamAPI_SteamNetworkingMessage_t_Release")
        && bind(api.SetSteamID64, "SteamAPI_SteamNetworkingIdentity_SetSteamID64")
        && bind(api.GetSteamID64, "SteamAPI_SteamNetworkingIdentity_GetSteamID64")
        && bind(api.InitRelay, "SteamAPI_ISteamNetworkingUtils_InitRelayNetworkAccess")
        && bind(api.GetFriendCount, "SteamAPI_ISteamFriends_GetFriendCount")
        && bind(api.GetFriendByIndex, "SteamAPI_ISteamFriends_GetFriendByIndex")
        && bind(api.GetFriendPersonaState, "SteamAPI_ISteamFriends_GetFriendPersonaState")
        && bind(api.GetFriendGamePlayed, "SteamAPI_ISteamFriends_GetFriendGamePlayed")
        && bind(api.InviteUserToGame, "SteamAPI_ISteamFriends_InviteUserToGame");
    ok = ok && api.Friends() && api.Matchmaking() && api.Messages() && api.Utils() && api.User();
    if (!ok) {
        failed = true;
        pc2_diagnostic_event(api.dll ? "net-stage:steam-bind-failed" : "net-stage:steam-dll-missing");
        queue("net:error|steam-api-unavailable");
        return false;
    }
    pc2_diagnostic_event("net-stage:steam-bound");
    api.InitRelay(api.Utils());
    self_id = api.GetSteamID(api.User());
    static Callback<LobbyEnter, 504> enter_cb(on_enter);
    static Callback<LobbyChatUpdate, 506> chat_cb(on_chat_update);
    static Callback<LobbyJoinRequested, 333> join_cb(on_join_requested);
    static Callback<SessionRequest, 1251> session_cb(on_session_request);
    enter_cb.Register(); chat_cb.Register(); join_cb.Register(); session_cb.Register();
    static CallResult<LobbyCreated, 513> created(on_created);
    static CallResult<LobbyEnter, 504> enter(on_enter_result);
    created_result = &created;
    enter_result = &enter;
    ready = true;
    std::string name;
    for (const char* p = api.GetPersonaName(api.Friends()); p && *p && name.size() < 64; ++p)
        if (*p != '|' && *p != '\n') name += *p;
    queue("net:ready|" + id_text(self_id) + "|" + name);
    pc2_diagnostic_event("net-stage:ready");
    // Started by accepting an invite while the game was closed: Steam passes the lobby.
    const wchar_t* line = GetCommandLineW();
    if (const wchar_t* at = wcsstr(line, L"+connect_lobby")) {
        u64 id = wcstoull(at + 14, nullptr, 10);
        if (id) queue("invite:accepted|" + id_text(id) + "|0|launch");
    }
    return true;
}

u64 parse_id(const std::string& text) { return strtoull(text.c_str(), nullptr, 10); }

void send_to(u64 id, const char* data, size_t size);

// File transfer and session memory --------------------------------------------------
// Files live next to PlanetCoaster2.exe, which the game addresses as "/run/".
// Lua module state is reset when a park loads, so a few session facts are kept here.
std::vector<std::pair<std::string, std::string>> memory;
constexpr size_t kChunk = 256 * 1024;

bool safe_name(const std::string& name) {
    if (name.empty() || name.size() > 64 || name[0] == '.') return false;
    for (char c : name) if (!(isalnum(static_cast<unsigned char>(c)) || c == '-' || c == '_' || c == '.')) return false;
    return name.rfind("pc2coop-", 0) == 0;
}

std::wstring game_path(const std::string& name) {
    wchar_t exe[MAX_PATH];
    DWORD length = GetModuleFileNameW(nullptr, exe, MAX_PATH);
    if (!length || length >= MAX_PATH) return L"";
    std::wstring path(exe, length);
    path = path.substr(0, path.find_last_of(L'\\') + 1);
    for (char c : name) path += static_cast<wchar_t>(c);
    return path;
}

void send_file(u64 to, const std::string& name, const std::string& as) {
    if (!safe_name(name) || !safe_name(as)) { queue("file:error|bad-name"); return; }
    HANDLE file = CreateFileW(game_path(name).c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING, 0, nullptr);
    if (file == INVALID_HANDLE_VALUE) { queue("file:error|open|" + name); return; }
    LARGE_INTEGER size{};
    GetFileSizeEx(file, &size);
    if (size.QuadPart <= 0 || size.QuadPart > 256LL * 1024 * 1024) { CloseHandle(file); queue("file:error|size|" + name); return; }
    std::vector<char> buffer(kChunk + 128);
    long long offset = 0;
    while (offset < size.QuadPart) {
        int header = sprintf_s(buffer.data(), 128, "\x02%s|%lld|%lld|", as.c_str(), size.QuadPart, offset);
        DWORD read = 0;
        if (header <= 0 || !ReadFile(file, buffer.data() + header, static_cast<DWORD>(kChunk), &read, nullptr) || !read) break;
        send_to(to, buffer.data(), static_cast<size_t>(header) + read);
        offset += read;
    }
    CloseHandle(file);
    queue("file:sent|" + id_text(to) + "|" + as + "|" + std::to_string(offset));
}

void receive_chunk(u64 from, const char* data, size_t size) {
    // 0x02 <name>|<total>|<offset>|<bytes>
    std::string head(data + 1, size - 1 < 160 ? size - 1 : 160);
    size_t a = head.find('|');
    size_t b = a == std::string::npos ? a : head.find('|', a + 1);
    size_t c = b == std::string::npos ? b : head.find('|', b + 1);
    if (c == std::string::npos) return;
    std::string name = head.substr(0, a);
    long long total = strtoll(head.substr(a + 1, b - a - 1).c_str(), nullptr, 10);
    long long offset = strtoll(head.substr(b + 1, c - b - 1).c_str(), nullptr, 10);
    if (!safe_name(name) || total <= 0 || total > 256LL * 1024 * 1024 || offset < 0 || offset >= total) return;
    const char* body = data + 1 + c + 1;
    size_t length = size - (1 + c + 1);
    HANDLE file = CreateFileW(game_path(name).c_str(), GENERIC_WRITE, 0, nullptr, offset == 0 ? CREATE_ALWAYS : OPEN_EXISTING, 0, nullptr);
    if (file == INVALID_HANDLE_VALUE) { queue("file:error|write|" + name); return; }
    LARGE_INTEGER at{};
    at.QuadPart = offset;
    SetFilePointerEx(file, at, nullptr, FILE_BEGIN);
    DWORD written = 0;
    WriteFile(file, body, static_cast<DWORD>(length), &written, nullptr);
    CloseHandle(file);
    const long long step = 512 * 1024;
    long long end = offset + static_cast<long long>(length);
    if (end < total && end / step != offset / step)
        queue("file:progress|" + name + "|" + std::to_string(end) + "|" + std::to_string(total));
    if (end >= total) queue("file:done|" + id_text(from) + "|" + name + "|" + std::to_string(total));
}

void remember(const std::string& key, const std::string& value) {
    for (auto& kv : memory) if (kv.first == key) { kv.second = value; return; }
    if (memory.size() < 32) memory.emplace_back(key, value);
}


void send_to(u64 id, const char* data, size_t size) {
    Identity peer = identity(id);
    int result = api.SendMessageToUser(api.Messages(), &peer, data, static_cast<unsigned int>(size), kReliable, kChannel);
    if (result != 1) queue("net:send-failed|" + id_text(id) + "|" + std::to_string(result));
}

// Commands: host | invite | join|<lobby> | leave | send|<steamid>|<payload> | all|<payload>
void command(const char* bytes, unsigned int size) {
    pc2_diagnostic_event("net-stage:command");
    if (!initialise()) return;
    std::string text(bytes, size);
    size_t bar = text.find('|');
    std::string verb = text.substr(0, bar);
    std::string rest = bar == std::string::npos ? "" : text.substr(bar + 1);
    if (verb == "host") {
        created_result->Set(api.CreateLobby(api.Matchmaking(), 1 /* friends only */, 8));
    } else if (verb == "invite") {
        if (lobby) api.ActivateInviteDialog(api.Friends(), lobby);
    } else if (verb == "join") {
        enter_result->Set(api.JoinLobby(api.Matchmaking(), parse_id(rest)));
    } else if (verb == "leave") {
        if (lobby) api.LeaveLobby(api.Matchmaking(), lobby);
        for (u64 m : members) { Identity peer = identity(m); api.CloseSession(api.Messages(), &peer); }
        lobby = 0;
        members.clear();
        memory.clear();
        api.SetRichPresence(api.Friends(), "connect", "");
        queue("lobby:left");
    } else if (verb == "send") {
        size_t split = rest.find('|');
        if (split == std::string::npos) return;
        u64 id = parse_id(rest.substr(0, split));
        if (is_member(id)) send_to(id, rest.data() + split + 1, rest.size() - split - 1);
    } else if (verb == "all") {
        for (u64 m : members) if (m != self_id) send_to(m, rest.data(), rest.size());
    } else if (verb == "file") {
        // file|<steamid>|<local name>|<remote name>
        size_t p1 = rest.find('|');
        size_t p2 = p1 == std::string::npos ? p1 : rest.find('|', p1 + 1);
        if (p2 == std::string::npos) return;
        u64 id = parse_id(rest.substr(0, p1));
        if (is_member(id)) send_file(id, rest.substr(p1 + 1, p2 - p1 - 1), rest.substr(p2 + 1));
    } else if (verb == "friends") {
        // friend|<id>|<name>|<persona state>|<1 if playing Planet Coaster 2>
        constexpr int kImmediate = 0x04;  // k_EFriendFlagImmediate
        int count = api.GetFriendCount(api.Friends(), kImmediate);
        queue("friends:begin|" + std::to_string(count));
        for (int i = 0; i < count && i < 250; ++i) {
            u64 id = api.GetFriendByIndex(api.Friends(), i, kImmediate);
            int state = api.GetFriendPersonaState(api.Friends(), id);
            unsigned char game[32] = {};
            bool playing = api.GetFriendGamePlayed(api.Friends(), id, game);
            u64 gameId = 0;
            std::memcpy(&gameId, game, sizeof(gameId));
            bool pc2 = playing && (gameId & 0xFFFFFF) == 2688950;
            queue("friend|" + id_text(id) + "|" + friend_name(id) + "|" + std::to_string(state) + "|" + (pc2 ? "1" : "0"));
        }
        queue("friends:end");
    } else if (verb == "invite_user") {
        u64 id = parse_id(rest);
        if (lobby && id) {
            std::string connect = "+connect_lobby " + id_text(lobby);
            bool ok = api.InviteUserToGame(api.Friends(), id, connect.c_str());
            queue(std::string(ok ? "invite:sent|" : "invite:failed|") + id_text(id));
        }
    } else if (verb == "kv") {
        size_t p1 = rest.find('|');
        if (p1 != std::string::npos) remember(rest.substr(0, p1), rest.substr(p1 + 1));
    } else if (verb == "status") {
        // A fresh Lua module (after a park load) asks for the session it belongs to.
        std::string name;
        for (const char* p = api.GetPersonaName(api.Friends()); p && *p && name.size() < 64; ++p)
            if (*p != '|' && *p != '\n') name += *p;
        queue("net:ready|" + id_text(self_id) + "|" + name);
        for (const auto& kv : memory) queue("kv|" + kv.first + "|" + kv.second);
        if (lobby) {
            u64 owner = api.GetLobbyOwner(api.Matchmaking(), lobby);
            queue("lobby:entered|" + id_text(lobby) + "|" + id_text(owner) + "|" + friend_name(owner));
        }
    }

}
}

void pc2_net_command(const char* bytes, unsigned int size) noexcept {
    try { command(bytes, size); } catch (...) { queue("net:error|command-exception"); }
}

namespace {
// F7 opens the in-game co-op menu. Polled here, only while the game window has focus.
void poll_key(int key, bool& down, const char* event) {
    bool pressed = (GetAsyncKeyState(key) & 0x8000) != 0;
    if (pressed && !down) {
        DWORD pid = 0;
        GetWindowThreadProcessId(GetForegroundWindow(), &pid);
        if (pid == GetCurrentProcessId()) queue(event);
    }
    down = pressed;
}

// F7 opens the multiplayer window, F8 the developer menu.
void poll_hotkeys() {
    static bool f7 = false, f8 = false;
    poll_key(VK_F7, f7, "key:menu");
    poll_key(VK_F8, f8, "key:dev");
}
}

// Returns one event string per call, or nothing when idle. Also drains Steam messages.
extern "C" __declspec(dllexport) int pc2_net_poll(void* state) noexcept {
    try {
        if (!initialise()) {
            AcquireSRWLockExclusive(&queue_lock);
            bool empty = events.empty();
            std::string event = empty ? "" : events.front();
            if (!empty) events.pop_front();
            ReleaseSRWLockExclusive(&queue_lock);
            return empty ? 0 : pc2_push_string(state, event.data(), event.size());
        }
        poll_hotkeys();
        Message* incoming[16];
        int count = api.ReceiveMessages(api.Messages(), kChannel, incoming, 16);
        for (int i = 0; i < count; ++i) {
            u64 from = api.GetSteamID64(&incoming[i]->peer);
            const char* data = static_cast<const char*>(incoming[i]->data);
            int size = incoming[i]->size;
            if (is_member(from) && size > 1 && data[0] == '\x02') {
                receive_chunk(from, data, static_cast<size_t>(size));
            } else if (is_member(from) && size > 0 && data[0] != '\x01') {
                queue("msg|" + id_text(from) + "|" + std::string(data, static_cast<size_t>(size)));
            }
            api.ReleaseMessage(incoming[i]);
        }
        AcquireSRWLockExclusive(&queue_lock);
        bool empty = events.empty();
        std::string event = empty ? "" : events.front();
        if (!empty) events.pop_front();
        ReleaseSRWLockExclusive(&queue_lock);
        if (empty) return 0;
        int pushed = pc2_push_string(state, event.data(), event.size());
        if (!pushed) pc2_diagnostic_event("net-stage:push-failed");
        return pushed;
    } catch (...) {
        return 0;
    }
}
