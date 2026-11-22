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
#include <memory>
#include <string>
#include <vector>
#include <cctype>
#include <utility>

void pc2_diagnostic_event(const char*) noexcept;
bool pc2_developer_mode() noexcept;
int pc2_push_string(void* state, const char* text, size_t size) noexcept;
std::string pc2_write_report(const std::string& args);

namespace {
// Visitor mode input (see poll_visitor).
bool visitor_keys = false, mouse_look = false;
ULONGLONG visitor_until = 0;
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
    bool (*SetGlobalConfigInt32)(void*, int, int) = nullptr;   // optional
    int (*GetFriendCount)(void*, int) = nullptr;
    u64 (*GetFriendByIndex)(void*, int, int) = nullptr;
    int (*GetFriendPersonaState)(void*, u64) = nullptr;
    bool (*GetFriendGamePlayed)(void*, u64, void*) = nullptr;
    bool (*InviteUserToGame)(void*, u64, const char*) = nullptr;
    bool (*HasFriend)(void*, u64, int) = nullptr;
    const char* (*GetFriendRichPresence)(void*, u64, const char*) = nullptr;
    void (*RequestFriendRichPresence)(void*, u64) = nullptr;
    int (*GetSmallFriendAvatar)(void*, u64) = nullptr;
    void* (*SteamUtils)() = nullptr;
    bool (*GetImageSize)(void*, int, unsigned int*, unsigned int*) = nullptr;
    bool (*GetImageRGBA)(void*, int, unsigned char*, int) = nullptr;
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

void drop_outbox(unsigned long long id);

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

// "1" when the lobby's owner is this player or one of their Steam friends. The session
// only takes a park from a friend: a lobby id can also reach the game from outside
// (launch arguments), and then nobody chose that host.
std::string owner_trust(u64 owner) {
    constexpr int kImmediate = 0x04;   // k_EFriendFlagImmediate
    return owner == self_id || api.HasFriend(api.Friends(), owner, kImmediate) ? "1" : "0";
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
            drop_outbox(id);
            Identity peer = identity(id);
            api.CloseSession(api.Messages(), &peer);
        }
    }
    members = now;
}

// Steam reports a JoinLobby twice: as the LobbyEnter callback and as the call result.
u64 failed_join = 0;
void entered(u64 id, unsigned int response) {
    if (response != 1) {
        // 2 = lobby no longer exists (old invite), 4 = full, 5 = error, 0 = no answer
        if (id != failed_join || id == 0) queue("lobby:join-failed|" + std::to_string(response));
        failed_join = id;
        return;
    }
    if (lobby == id) return;
    lobby = id;
    u64 owner = api.GetLobbyOwner(api.Matchmaking(), lobby);
    std::string connect = "+connect_lobby " + id_text(lobby);
    api.SetRichPresence(api.Friends(), "connect", connect.c_str());
    api.SetRichPresence(api.Friends(), "status", "PC2 Co-op");
    members.clear();
    refresh_members();
    queue("lobby:entered|" + id_text(lobby) + "|" + id_text(owner) + "|" + friend_name(owner) + "|" + owner_trust(owner));
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
void on_enter(const LobbyEnter& data) { entered(data.lobby, data.response); }
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
void on_enter_result(const LobbyEnter& data, bool failure) { entered(failure ? 0 : data.lobby, failure ? 0 : data.response); }

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
        && bind(api.InviteUserToGame, "SteamAPI_ISteamFriends_InviteUserToGame")
        && bind(api.HasFriend, "SteamAPI_ISteamFriends_HasFriend")
        && bind(api.GetFriendRichPresence, "SteamAPI_ISteamFriends_GetFriendRichPresence")
        && bind(api.RequestFriendRichPresence, "SteamAPI_ISteamFriends_RequestFriendRichPresence")
        && bind(api.GetSmallFriendAvatar, "SteamAPI_ISteamFriends_GetSmallFriendAvatar")
        && bind(api.SteamUtils, "SteamAPI_SteamUtils_v010")
        && bind(api.GetImageSize, "SteamAPI_ISteamUtils_GetImageSize")
        && bind(api.GetImageRGBA, "SteamAPI_ISteamUtils_GetImageRGBA");
    ok = ok && api.Friends() && api.Matchmaking() && api.Messages() && api.Utils() && api.User();
    if (!ok) {
        failed = true;
        pc2_diagnostic_event(api.dll ? "net-stage:steam-bind-failed" : "net-stage:steam-dll-missing");
        queue("net:error|steam-api-unavailable");
        return false;
    }
    pc2_diagnostic_event("net-stage:steam-bound");
    api.InitRelay(api.Utils());
    // Reliable data defaults to 256 KB/s, which makes the park transfer take a minute or
    // more. Allow 1 MB/s; the outbox below handles "buffer full" either way.
    if (bind(api.SetGlobalConfigInt32, "SteamAPI_ISteamNetworkingUtils_SetGlobalConfigValueInt32")) {
        constexpr int kSendRateMin = 10, kSendRateMax = 11;   // ESteamNetworkingConfigValue
        bool a = api.SetGlobalConfigInt32(api.Utils(), kSendRateMin, 1024 * 1024);
        bool b = api.SetGlobalConfigInt32(api.Utils(), kSendRateMax, 1024 * 1024);
        pc2_diagnostic_event(a && b ? "net-stage:send-rate-1MB" : "net-stage:send-rate-default");
    }
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

// pc2coop-ride-<number>-<number>.blueprint: a ride snapshot (see rides.lua).
bool ride_name(const std::string& name) {
    const std::string head = "pc2coop-ride-", tail = ".blueprint";
    if (name.size() <= head.size() + tail.size() || name.rfind(head, 0) != 0) return false;
    if (name.compare(name.size() - tail.size(), tail.size(), tail) != 0) return false;
    std::string middle = name.substr(head.size(), name.size() - head.size() - tail.size());
    size_t dash = middle.find('-');
    if (dash == std::string::npos || dash == 0 || dash + 1 >= middle.size() || dash > 20 || middle.size() - dash - 1 > 10) return false;
    for (size_t i = 0; i < middle.size(); ++i) if (i != dash && !isdigit(static_cast<unsigned char>(middle[i]))) return false;
    return true;
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

// Ordered outbox per peer. Steam refuses reliable sends while its send buffer is full
// (k_EResultLimitExceeded = 25) or while the session is still connecting (observed: 35);
// refused data waits here and every poll retries it, so nothing is dropped and the order
// (messages, file chunks) is kept. Files are read one chunk at a time, only when Steam has
// room. A peer that accepts nothing for kStallMs is given up on, loudly.
constexpr ULONGLONG kStallMs = 60000;
struct OutFile { std::string as; std::wstring path; long long total = 0; long long offset = 0; long long reported = 0; };
struct OutItem { std::string data; std::shared_ptr<OutFile> file; };
struct Outbox { u64 id = 0; std::deque<OutItem> items; ULONGLONG progress = 0; };
std::vector<Outbox> outbox;

Outbox& outbox_for(u64 id) {
    for (auto& entry : outbox) if (entry.id == id) return entry;
    outbox.push_back(Outbox{id, {}, GetTickCount64()});
    return outbox.back();
}

void drop_outbox(u64 id) {
    for (auto& entry : outbox) if (entry.id == id) entry.items.clear();
}

int raw_send(u64 id, const char* data, size_t size) {
    Identity peer = identity(id);
    return api.SendMessageToUser(api.Messages(), &peer, data, static_cast<unsigned int>(size), kReliable, kChannel);
}

// Sends the next chunk of a file. 1 = sent (offset advanced), anything else = try again later.
int send_chunk(u64 id, OutFile& file) {
    HANDLE handle = CreateFileW(file.path.c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING, 0, nullptr);
    if (handle == INVALID_HANDLE_VALUE) return -1;
    std::vector<char> buffer(kChunk + 128);
    int header = sprintf_s(buffer.data(), 128, "\x02%s|%lld|%lld|", file.as.c_str(), file.total, file.offset);
    LARGE_INTEGER at{};
    at.QuadPart = file.offset;
    DWORD read = 0;
    bool ok = header > 0 && SetFilePointerEx(handle, at, nullptr, FILE_BEGIN)
        && ReadFile(handle, buffer.data() + header, static_cast<DWORD>(kChunk), &read, nullptr) && read;
    CloseHandle(handle);
    if (!ok) return -1;
    int result = raw_send(id, buffer.data(), static_cast<size_t>(header) + read);
    if (result == 1) file.offset += read;
    return result;
}

void pump_outbox() {
    int budget = 32;
    ULONGLONG now = GetTickCount64();
    for (auto& entry : outbox) {
        auto& items = entry.items;
        if (items.empty()) { entry.progress = now; continue; }
        while (!items.empty() && budget > 0) {
            --budget;
            OutItem& item = items.front();
            int result = item.file ? send_chunk(entry.id, *item.file)
                                   : raw_send(entry.id, item.data.data(), item.data.size());
            if (result != 1) {
                if (now - entry.progress < kStallMs) break;   // retry on the next poll
                queue("net:peer-stalled|" + id_text(entry.id) + "|" + std::to_string(result) + "|"
                      + std::to_string(items.size()));
                items.clear();
                break;
            }
            entry.progress = now;
            if (!item.file) { items.pop_front(); continue; }
            if (item.file->offset - item.file->reported >= 1024 * 1024 && item.file->offset < item.file->total) {
                item.file->reported = item.file->offset;
                queue("file:sending|" + id_text(entry.id) + "|" + item.file->as + "|" + std::to_string(item.file->offset)
                      + "|" + std::to_string(item.file->total));
            }
            if (item.file->offset >= item.file->total) {
                queue("file:sent|" + id_text(entry.id) + "|" + item.file->as + "|" + std::to_string(item.file->total));
                items.pop_front();
            }
        }
    }
}

void send_file(u64 to, const std::string& name, const std::string& as) {
    if (!safe_name(name) || !safe_name(as)) { queue("file:error|bad-name"); return; }
    HANDLE file = CreateFileW(game_path(name).c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING, 0, nullptr);
    if (file == INVALID_HANDLE_VALUE) { queue("file:error|open|" + name); return; }
    LARGE_INTEGER size{};
    GetFileSizeEx(file, &size);
    CloseHandle(file);
    if (size.QuadPart <= 0 || size.QuadPart > 256LL * 1024 * 1024) { queue("file:error|size|" + name); return; }
    auto out = std::make_shared<OutFile>();
    out->as = as;
    out->path = game_path(name);
    out->total = size.QuadPart;
    outbox_for(to).items.push_back(OutItem{std::string(), out});
    queue("file:queued|" + id_text(to) + "|" + as + "|" + std::to_string(size.QuadPart));
    pump_outbox();
}

// Ride snapshots a peer may start per game start (rides.lua keeps 40 per author and deletes
// older ones; 400 leaves room for long sessions and stops a flood at 400 x 16 MB).
constexpr int kRideFilesPerPeer = 400;
std::vector<std::pair<u64, int>> ride_files;

bool ride_file_allowed(u64 from) {
    for (auto& entry : ride_files) {
        if (entry.first == from) return ++entry.second <= kRideFilesPerPeer;
    }
    ride_files.emplace_back(from, 1);
    return true;
}

// True while this game loads the transferred park (the Lua side stores phase=loading).
bool files_locked() {
    for (const auto& kv : memory) if (kv.first == "phase") return kv.second == "loading";
    return false;
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
    // Only the host of the lobby this game joined sends files: the park it shares, and
    // snapshots of rides (coasters) as blueprint files. The host also takes ride snapshots
    // from its members, to check and pass on. Anything else is dropped.
    u64 owner = lobby ? api.GetLobbyOwner(api.Matchmaking(), lobby) : 0;
    if (!owner) return;
    if (ride_name(name)) {
        if (total > 16LL * 1024 * 1024 || !is_member(from) || from == self_id) return;
        if (owner != self_id && from != owner) return;
        // Security review 2026-11-21: on the host a member sends only its own snapshots
        // (pc2coop-ride-<its id>-<n>), so nobody overwrites another player's ride, and only so
        // many per game start, so nobody fills the disk (16 MB each).
        if (owner == self_id && name.rfind("pc2coop-ride-" + id_text(from) + "-", 0) != 0) return;
        if (offset == 0 && !ride_file_allowed(from)) { queue("file:error|ride-limit|" + id_text(from)); return; }
    } else {
        if (owner == self_id || from != owner) return;
        if (name != "pc2coop-join.bin" && name != "pc2coop-join.trn") return;
        if (files_locked()) return;
    }
    const char* body = data + 1 + c + 1;
    size_t length = size - (1 + c + 1);
    if (static_cast<long long>(length) > total - offset) return;
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

// Profile pictures -------------------------------------------------------------------------
// Steam hands out RGBA pixels; the UI shows them as a PNG data URL. The PNG is written
// uncompressed (zlib "stored" blocks): 32x32 pixels are about 4 KB.
unsigned int crc32(const unsigned char* data, size_t size, unsigned int crc = 0) {
    crc = ~crc;
    for (size_t i = 0; i < size; ++i) {
        crc ^= data[i];
        for (int k = 0; k < 8; ++k) crc = (crc >> 1) ^ (0xEDB88320u & (0u - (crc & 1u)));
    }
    return ~crc;
}

void put32(std::string& out, unsigned int v) {
    out += static_cast<char>(v >> 24); out += static_cast<char>(v >> 16); out += static_cast<char>(v >> 8); out += static_cast<char>(v);
}

void chunk(std::string& png, const char* type, const std::string& data) {
    put32(png, static_cast<unsigned int>(data.size()));
    std::string body = std::string(type, 4) + data;
    png += body;
    put32(png, crc32(reinterpret_cast<const unsigned char*>(body.data()), body.size()));
}

std::string png_rgba(const unsigned char* rgba, unsigned int w, unsigned int h) {
    std::string raw;
    for (unsigned int y = 0; y < h; ++y) {
        raw += '\0';
        raw.append(reinterpret_cast<const char*>(rgba + static_cast<size_t>(y) * w * 4), static_cast<size_t>(w) * 4);
    }
    std::string z = "\x78\x01";
    unsigned int a = 1, b = 0;
    for (unsigned char c : raw) { a = (a + c) % 65521; b = (b + a) % 65521; }
    for (size_t at = 0; at < raw.size() || at == 0; at += 65535) {
        size_t n = raw.size() - at < 65535 ? raw.size() - at : 65535;
        z += static_cast<char>(at + n >= raw.size() ? 1 : 0);
        z += static_cast<char>(n & 0xff); z += static_cast<char>(n >> 8);
        z += static_cast<char>(~n & 0xff); z += static_cast<char>((~n >> 8) & 0xff);
        z.append(raw, at, n);
        if (at + n >= raw.size()) break;
    }
    put32(z, (b << 16) | a);
    std::string ihdr;
    put32(ihdr, w); put32(ihdr, h);
    ihdr += "\x08\x06"; ihdr += std::string(3, '\0');
    std::string png = "\x89PNG\r\n\x1a\n";
    chunk(png, "IHDR", ihdr);
    chunk(png, "IDAT", z);
    chunk(png, "IEND", std::string());
    return png;
}

std::string base64(const std::string& in) {
    static const char* table = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    std::string out;
    size_t i = 0;
    for (; i + 2 < in.size(); i += 3) {
        unsigned int v = (static_cast<unsigned char>(in[i]) << 16) | (static_cast<unsigned char>(in[i + 1]) << 8) | static_cast<unsigned char>(in[i + 2]);
        out += table[v >> 18]; out += table[(v >> 12) & 63]; out += table[(v >> 6) & 63]; out += table[v & 63];
    }
    if (i < in.size()) {
        unsigned int v = static_cast<unsigned char>(in[i]) << 16;
        if (i + 1 < in.size()) v |= static_cast<unsigned char>(in[i + 1]) << 8;
        out += table[v >> 18]; out += table[(v >> 12) & 63];
        out += i + 1 < in.size() ? table[(v >> 6) & 63] : '=';
        out += '=';
    }
    return out;
}

std::vector<u64> avatar_waiting;   // pictures Steam is still downloading

// "avatar|<sid>|<base64 png>" (empty when the player has none). False while Steam loads it.
bool send_avatar(u64 id) {
    int image = api.GetSmallFriendAvatar(api.Friends(), id);
    if (image == -1) return false;
    unsigned int w = 0, h = 0;
    std::string data;
    if (image > 0 && api.GetImageSize(api.SteamUtils(), image, &w, &h) && w && h && w <= 64 && h <= 64) {
        std::vector<unsigned char> rgba(static_cast<size_t>(w) * h * 4);
        if (api.GetImageRGBA(api.SteamUtils(), image, rgba.data(), static_cast<int>(rgba.size()))) data = base64(png_rgba(rgba.data(), w, h));
    }
    queue("avatar|" + id_text(id) + "|" + data);
    return true;
}

void retry_avatars() {
    static int tick = 0;
    if (avatar_waiting.empty() || ++tick % 30) return;
    std::vector<u64> still;
    for (u64 id : avatar_waiting) if (!send_avatar(id)) still.push_back(id);
    avatar_waiting = still;
}

// Folders of other mods next to the game's content (names only).
std::string mod_list() {
    std::wstring dir = game_path("pc2coop-x");
    dir = dir.substr(0, dir.find_last_of(L'\\') + 1) + L"Win64\\ovldata\\*";
    WIN32_FIND_DATAW found{};
    HANDLE find = FindFirstFileW(dir.c_str(), &found);
    std::string list;
    if (find == INVALID_HANDLE_VALUE) return list;
    int count = 0;
    do {
        if (!(found.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) || found.cFileName[0] == L'.') continue;
        std::wstring name = found.cFileName;
        if (name.rfind(L"Content", 0) == 0 || name == L"GameMain" || name == L"PC2CoopProbe") continue;
        std::string ascii;
        for (wchar_t c : name) if (c < 128 && c != L'|' && c != L';') ascii += static_cast<char>(c);
        if (ascii.empty() || ++count > 40) continue;
        list += (list.empty() ? "" : ";") + ascii.substr(0, 48);
    } while (FindNextFileW(find, &found));
    FindClose(find);
    return list;
}

// Small text files the mod keeps between game starts, next to the game's exe: who built
// what in a park (pc2coop-authors-<park>.txt), ride ratings of visitors
// (pc2coop-ratings-<park>.txt) and the last session (pc2coop-lastsession.txt).
// Only these names; nothing received from the network decides about them.
bool note_name(const std::string& name) {
    if (!safe_name(name) || name.size() < 5 || name.compare(name.size() - 4, 4, ".txt") != 0) return false;
    return name == "pc2coop-lastsession.txt" || name.rfind("pc2coop-authors-", 0) == 0
        || name.rfind("pc2coop-ratings-", 0) == 0 || name.rfind("pc2coop-board-", 0) == 0
        || name.rfind("pc2coop-visits-", 0) == 0;
}

void note_write(const std::string& name, const std::string& data, bool append) {
    if (!note_name(name) || data.size() > 4096) return;
    HANDLE file = CreateFileW(game_path(name).c_str(), append ? FILE_APPEND_DATA : GENERIC_WRITE, 0, nullptr,
                              append ? OPEN_ALWAYS : CREATE_ALWAYS, 0, nullptr);
    if (file == INVALID_HANDLE_VALUE) { queue("note:error|" + name); return; }
    LARGE_INTEGER size{};
    // A runaway file is cut off at 2 MB rather than filling the disk.
    if (!append || (GetFileSizeEx(file, &size) && size.QuadPart < 2 * 1024 * 1024)) {
        DWORD written = 0;
        WriteFile(file, data.data(), static_cast<DWORD>(data.size()), &written, nullptr);
    }
    CloseHandle(file);
}

// Sends the file back as "note:data|name|<up to 3000 bytes>" events, then "note:end|name".
void note_read(const std::string& name) {
    if (!note_name(name)) return;
    HANDLE file = CreateFileW(game_path(name).c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING, 0, nullptr);
    if (file != INVALID_HANDLE_VALUE) {
        std::vector<char> buffer(3000);
        long long total = 0;
        DWORD read = 0;
        while (total < 2 * 1024 * 1024 && ReadFile(file, buffer.data(), static_cast<DWORD>(buffer.size()), &read, nullptr) && read) {
            queue("note:data|" + name + "|" + std::string(buffer.data(), read));
            total += read;
        }
        CloseHandle(file);
    }
    queue("note:end|" + name);
}

void remember(const std::string& key, const std::string& value) {
    for (auto& kv : memory) if (kv.first == key) { kv.second = value; return; }
    if (memory.size() < 32) memory.emplace_back(key, value);
}


void send_to(u64 id, const char* data, size_t size) {
    auto& box = outbox_for(id);
    if (box.items.empty()) {
        box.progress = GetTickCount64();
        if (raw_send(id, data, size) == 1) return;
    }
    box.items.push_back(OutItem{std::string(data, size), nullptr});
}

// Commands: host | invite | join|<lobby> | leave | send|<steamid>|<payload> | all|<payload>
void command(const char* bytes, unsigned int size) {
    std::string text(bytes, size);
    size_t bar = text.find('|');
    std::string verb = text.substr(0, bar);
    std::string rest = bar == std::string::npos ? "" : text.substr(bar + 1);
    // The problem report (FEAT-223) also works when Steam is not there.
    if (verb == "report") { queue(pc2_write_report(rest)); return; }
    static int logged = 0;
    if (logged < 3) { ++logged; pc2_diagnostic_event("net-stage:command"); }
    if (!initialise()) return;
    if (verb == "host") {
        created_result->Set(api.CreateLobby(api.Matchmaking(), 1 /* friends only */, 8));
    } else if (verb == "invite") {
        if (lobby) api.ActivateInviteDialog(api.Friends(), lobby);
    } else if (verb == "join") {
        failed_join = 0;
        enter_result->Set(api.JoinLobby(api.Matchmaking(), parse_id(rest)));
    } else if (verb == "leave") {
        if (lobby) api.LeaveLobby(api.Matchmaking(), lobby);
        for (u64 m : members) { Identity peer = identity(m); api.CloseSession(api.Messages(), &peer); }
        lobby = 0;
        members.clear();
        memory.clear();
        outbox.clear();
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
            // A friend in a PC2Coop lobby advertises it in rich presence ("+connect_lobby <id>").
            std::string open;
            if (pc2) {
                api.RequestFriendRichPresence(api.Friends(), id);
                const char* connect = api.GetFriendRichPresence(api.Friends(), id, "connect");
                if (connect && std::strncmp(connect, "+connect_lobby ", 15) == 0) {
                    u64 their = strtoull(connect + 15, nullptr, 10);
                    if (their) open = id_text(their);
                }
            }
            queue("friend|" + id_text(id) + "|" + friend_name(id) + "|" + std::to_string(state) + "|" + (pc2 ? "1" : "0") + "|" + open);
        }
        queue("friends:end");
    } else if (verb == "invite_user") {
        u64 id = parse_id(rest);
        if (lobby && id) {
            std::string connect = "+connect_lobby " + id_text(lobby);
            bool ok = api.InviteUserToGame(api.Friends(), id, connect.c_str());
            queue(std::string(ok ? "invite:sent|" : "invite:failed|") + id_text(id));
        }
    } else if (verb == "note-write" || verb == "note-append") {
        // note-write|<name>|<text>  /  note-append|<name>|<text>
        size_t bar2 = rest.find('|');
        if (bar2 != std::string::npos) note_write(rest.substr(0, bar2), rest.substr(bar2 + 1), verb == "note-append");
    } else if (verb == "avatar") {
        u64 id = parse_id(rest);
        if (id && !send_avatar(id)) avatar_waiting.push_back(id);
    } else if (verb == "now") {
        // Real time in milliseconds (competition timers; frames depend on the frame rate).
        queue("now|" + std::to_string(GetTickCount64()));
    } else if (verb == "visitor") {
        // visitor|<1 keys>|<1 mouse look>
        visitor_keys = rest.size() >= 1 && rest[0] == '1';
        mouse_look = rest.size() >= 3 && rest[2] == '1';
        visitor_until = GetTickCount64() + 2000;
    } else if (verb == "mods") {
        queue("mods|" + mod_list());
    } else if (verb == "note-read") {
        note_read(rest);
    } else if (verb == "del") {
        // Temporary park copies of a finished transfer (pc2coop-host-<id>.*, pc2coop-join.*).
        if (safe_name(rest)) DeleteFileW(game_path(rest).c_str());
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
            queue("lobby:entered|" + id_text(lobby) + "|" + id_text(owner) + "|" + friend_name(owner) + "|" + owner_trust(owner));
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

// Middle mouse button: Lua pings on a short click; holding it turns the camera, which Lua
// tells apart by the press time, the cursor travel and whether the camera moved.
void poll_middle_button() {
    static bool down = false;
    static ULONGLONG at = 0;
    static POINT from{};
    bool pressed = (GetAsyncKeyState(VK_MBUTTON) & 0x8000) != 0;
    DWORD pid = 0;
    GetWindowThreadProcessId(GetForegroundWindow(), &pid);
    bool ours = pid == GetCurrentProcessId();
    if (pressed && !down && ours) {
        at = GetTickCount64();
        GetCursorPos(&from);
        queue("key:mdown");
    } else if (!pressed && down && at) {
        POINT to{};
        GetCursorPos(&to);
        long long dx = to.x - from.x, dy = to.y - from.y;
        if (ours) queue("key:mup|" + std::to_string(GetTickCount64() - at) + "|" + std::to_string(dx * dx + dy * dy));
        at = 0;
    }
    down = pressed;
}

// Visitor mode (switched on by Lua with "visitor|<keys>|<mouse look>", renewed every second):
// Tab, T, E, V, F and 1-6 go to Lua as "key:v|<name>|<1 down, 0 up>" (Lua ignores 1-6 since P6).
// With mouse look the cursor is hidden, kept in the middle of the game window and its travel
// goes to Lua as "mouse|dx|dy".
// Without a renewal for two seconds everything switches off, so the cursor is never caught.

// The cursor is hidden while mouse look holds it in the middle (P6 finding A10): before, it stood
// visible in the centre of the screen. ShowCursor only counts for the thread that calls it, and
// this runs on the game's Lua thread, not the window's: the cursor stayed (owner's test
// 2026-11-22). So the game window's WM_SETCURSOR (sent on the window's thread whenever the
// mouse moves, also by SetCursorPos) sets no cursor while hidden. The DLL is pinned, so the
// window procedure below stays valid for the whole game.
WNDPROC original_proc = nullptr;
HWND cursor_window = nullptr;
volatile LONG cursor_off = 0;

LRESULT CALLBACK cursor_proc(HWND window, UINT message, WPARAM wparam, LPARAM lparam) {
    if (message == WM_SETCURSOR && cursor_off && LOWORD(lparam) == HTCLIENT) {
        SetCursor(nullptr);
        return TRUE;
    }
    return CallWindowProcW(original_proc, window, message, wparam, lparam);
}

void set_cursor_hidden(bool hide) {
    static bool hidden = false;
    if (hide && !cursor_window) {
        HWND window = GetForegroundWindow();
        DWORD pid = 0;
        GetWindowThreadProcessId(window, &pid);
        if (window && pid == GetCurrentProcessId() && IsWindowUnicode(window)) {
            original_proc = reinterpret_cast<WNDPROC>(SetWindowLongPtrW(window, GWLP_WNDPROC, reinterpret_cast<LONG_PTR>(cursor_proc)));
            if (original_proc) cursor_window = window;
        }
    }
    InterlockedExchange(&cursor_off, hide ? 1 : 0);
    if (hide == hidden) return;
    hidden = hide;
    ShowCursor(hide ? FALSE : TRUE);
}

void poll_visitor() {
    if (!visitor_keys && !mouse_look) { set_cursor_hidden(false); return; }
    if (GetTickCount64() > visitor_until) { visitor_keys = mouse_look = false; set_cursor_hidden(false); return; }
    HWND window = GetForegroundWindow();
    DWORD pid = 0;
    GetWindowThreadProcessId(window, &pid);
    if (pid != GetCurrentProcessId()) { set_cursor_hidden(false); return; }
    set_cursor_hidden(mouse_look);
    static bool down[12] = {};
    static const int keys[12] = {VK_TAB, 'T', 'E', 'V', '1', '2', '3', '4', '5', '6', 'F', VK_SPACE};
    static const char* names[12] = {"tab", "t", "e", "v", "1", "2", "3", "4", "5", "6", "f", "space"};
    for (int i = 0; visitor_keys && i < 12; ++i) {
        bool pressed = (GetAsyncKeyState(keys[i]) & 0x8000) != 0;
        if (pressed != down[i]) {
            down[i] = pressed;
            queue(std::string("key:v|") + names[i] + "|" + (pressed ? "1" : "0"));
        }
    }
    if (mouse_look) {
        RECT rect{};
        if (!GetClientRect(window, &rect)) return;
        POINT centre{(rect.right - rect.left) / 2, (rect.bottom - rect.top) / 2};
        ClientToScreen(window, &centre);
        POINT at{};
        GetCursorPos(&at);
        long dx = at.x - centre.x, dy = at.y - centre.y;
        if (dx || dy) {
            queue("mouse|" + std::to_string(dx) + "|" + std::to_string(dy));
            SetCursorPos(centre.x, centre.y);
        }
    }
}

// F7 opens the multiplayer window, Enter the chat (Lua and the UI decide whether it opens:
// only in a park, never while a text field of the game has the keyboard). F8 opens the
// developer dialog and only exists with the developer marker file (TP-31).
void poll_hotkeys() {
    static bool f7 = false, f8 = false, enter = false;
    poll_key(VK_F7, f7, "key:menu");
    if (pc2_developer_mode()) poll_key(VK_F8, f8, "key:dev");
    poll_key(VK_RETURN, enter, "key:chat");
    poll_middle_button();
    poll_visitor();
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
        pump_outbox();
        retry_avatars();
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
