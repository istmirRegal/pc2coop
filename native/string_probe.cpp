// Original MIT code. Current-build-only call to the game's own string allocator.
// No stock Lua layout writes, no engine calls on background threads.
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <bcrypt.h>
#include <cstdint>
#include <cstring>
#include <memory>
#include <new>
void pc2_diagnostic_event(const char*) noexcept;
bool pc2_diagnostic_inbox(char*, DWORD, DWORD*) noexcept;

namespace {
using PushString = const char* (*)(void*, const char*, size_t);
PushString push_string = nullptr;
DWORD lua_thread = 0;
bool checked = false;
constexpr unsigned char expected_hash[32] = {
    0x9d,0xa9,0x0a,0xe2,0x61,0x1b,0xf4,0x1a,0xf5,0x32,0xa3,0x06,0x11,0x08,0x2b,0xd9,
    0x0c,0xdd,0xa6,0xb3,0x25,0xe5,0x70,0xac,0x63,0xa4,0x69,0x05,0x1e,0x73,0x6c,0x12};
constexpr unsigned char expected_code[] = {
    0x48,0x89,0x5c,0x24,0x10,0x57,0x48,0x83,0xec,0x20,0x8b,0x05,0x3c,0xa7,0x55,0x01,
    0x48,0x8b,0xf9,0xff,0xc0,0x89,0x05,0x31,0xa7,0x55,0x01,0x89,0x41,0xf0,0x4d,0x85,
    0xc0,0x75,0x71,0x48,0x89,0x74,0x24,0x30,0x4c,0x8d,0x0d,0x66,0xe3,0x1a,0x01,0xb8,
    0xb3,0xcf,0x21,0x35,0x41,0x8b,0xf1,0x41,0xf7,0xe1,0x41,0x8b,0xc1,0x2b,0xc2,0xd1};

bool matching_executable() noexcept {
    // Engine callback stacks may be small. Keep path and streaming buffers off stack.
    std::unique_ptr<wchar_t[]> path(new (std::nothrow) wchar_t[32768]);
    std::unique_ptr<unsigned char[]> buffer(new (std::nothrow) unsigned char[65536]);
    if (!path || !buffer) return false;
    DWORD length = GetModuleFileNameW(nullptr, path.get(), 32768);
    if (!length || length >= 32768) return false;
    HANDLE file = CreateFileW(path.get(), GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_DELETE,
                             nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (file == INVALID_HANDLE_VALUE) return false;
    LARGE_INTEGER size;
    bool ok = GetFileSizeEx(file, &size) && size.QuadPart == 301397504;
    pc2_diagnostic_event(ok ? "native-stage:exe-size-matched" : "native-stage:exe-size-rejected");
    BCRYPT_ALG_HANDLE algorithm = nullptr;
    BCRYPT_HASH_HANDLE hash = nullptr;
    if (ok) ok = BCryptOpenAlgorithmProvider(&algorithm, BCRYPT_SHA256_ALGORITHM, nullptr, 0) >= 0;
    if (ok) ok = BCryptCreateHash(algorithm, &hash, nullptr, 0, nullptr, 0, 0) >= 0;
    pc2_diagnostic_event(ok ? "native-stage:hash-provider-ready" : "native-stage:hash-provider-rejected");
    unsigned long long total = 0;
    while (ok) {
        DWORD count = 0;
        if (!ReadFile(file, buffer.get(), 65536, &count, nullptr)) { ok = false; break; }
        if (!count) break;
        total += count;
        if (total > 301397504) { ok = false; break; }
        ok = BCryptHashData(hash, buffer.get(), count, 0) >= 0;
    }
    unsigned char digest[32];
    if (ok) ok = total == 301397504 && BCryptFinishHash(hash, digest, sizeof(digest), 0) >= 0
        && std::memcmp(digest, expected_hash, sizeof(digest)) == 0;
    if (hash) BCryptDestroyHash(hash);
    if (algorithm) BCryptCloseAlgorithmProvider(algorithm, 0);
    CloseHandle(file);
    return ok;
}

bool region(const void* address, size_t length, bool writable, bool executable) noexcept {
    MEMORY_BASIC_INFORMATION info{};
    if (!address || !VirtualQuery(address, &info, sizeof(info)) || info.State != MEM_COMMIT
        || (info.Protect & (PAGE_GUARD | PAGE_NOACCESS))) return false;
    auto start = reinterpret_cast<uintptr_t>(address);
    auto base = reinterpret_cast<uintptr_t>(info.BaseAddress);
    if (start < base || length > info.RegionSize || start-base > info.RegionSize-length) return false;
    DWORD protection = info.Protect & 0xff;
    if (writable && protection != PAGE_READWRITE && protection != PAGE_WRITECOPY
        && protection != PAGE_EXECUTE_READWRITE && protection != PAGE_EXECUTE_WRITECOPY) return false;
    if (executable && protection != PAGE_EXECUTE_READ && protection != PAGE_EXECUTE_READWRITE
        && protection != PAGE_EXECUTE_WRITECOPY && protection != PAGE_EXECUTE) return false;
    return true;
}

bool initialize() noexcept {
    if (checked) return push_string != nullptr;
    checked = true;
    pc2_diagnostic_event("native-stage:hash-begin");
    if (!matching_executable()) { pc2_diagnostic_event("native-stage:hash-rejected"); return false; }
    pc2_diagnostic_event("native-stage:hash-matched");
    auto base = reinterpret_cast<unsigned char*>(GetModuleHandleW(nullptr));
    auto dos = reinterpret_cast<IMAGE_DOS_HEADER*>(base);
    if (dos->e_magic != IMAGE_DOS_SIGNATURE || dos->e_lfanew < 0 || dos->e_lfanew > 4096) return false;
    auto pe = reinterpret_cast<IMAGE_NT_HEADERS64*>(base + dos->e_lfanew);
    if (pe->Signature != IMAGE_NT_SIGNATURE || pe->FileHeader.Machine != IMAGE_FILE_MACHINE_AMD64
        || pe->OptionalHeader.Magic != IMAGE_NT_OPTIONAL_HDR64_MAGIC
        || pe->OptionalHeader.SizeOfImage <= 0x1e2a024) return false;
    auto target = base + 0x1e29f50;
    if (!region(target, sizeof(expected_code), false, true)
        || std::memcmp(target, expected_code, sizeof(expected_code)) != 0) return false;
    push_string = reinterpret_cast<PushString>(target);
    lua_thread = GetCurrentThreadId();
    pc2_diagnostic_event("native-stage:code-matched");
    return true;
}

void reject(const char* reason) noexcept {
    static int reported = 0;
    if (reported < 8) { ++reported; pc2_diagnostic_event(reason); }
}

int push(void* state, const char* text, size_t size) noexcept {
    if (!initialize()) { reject("push-reject:init"); return 0; }
    // The game runs park managers on a different OS thread than the frontend. A Lua
    // call into this function always supplies the state executing on the current
    // thread, so the state checks below are the real guard, not the thread id.
    auto l = reinterpret_cast<unsigned char*>(state);
    if (reinterpret_cast<uintptr_t>(l) < 0x10000 || !region(l-16, 56, true, false)) { reject("push-reject:state"); return 0; }
    // Only validate observed fields. The game routine owns allocations, tags and GC.
    void* top = nullptr;
    void* call_info = nullptr;
    std::memcpy(&top, l+0x10, sizeof(top));
    std::memcpy(&call_info, l+0x20, sizeof(call_info));
    if (!region(top, 24, true, false) || !region(call_info, 8, false, false)) { reject("push-reject:top"); return 0; }
    void* function = nullptr;
    std::memcpy(&function, call_info, sizeof(function));
    auto begin = reinterpret_cast<uintptr_t>(function);
    auto end = reinterpret_cast<uintptr_t>(top);
    if (!region(function, 24, false, false) || end < begin+24 || end-begin > 24*65536
        || (end-begin)%24 != 0) { reject("push-reject:frame"); return 0; }
    static bool first = true;
    const bool report = first;
    first = false;
    if (report) pc2_diagnostic_event("native-stage:state-valid; calling-game-string");
    push_string(state, text, size);
    if (report) pc2_diagnostic_event("native-stage:game-string-returned");
    return 1;
}
}

int pc2_push_string(void* state, const char* text, size_t size) noexcept {
    return push(state, text, size);
}

extern "C" __declspec(dllexport) int pc2_probe_greeting(void* state) noexcept {
    constexpr char text[] = "PC2Coop native return OK";
    return push(state, text, sizeof(text)-1);
}
extern "C" __declspec(dllexport) int pc2_probe_empty(void* state) noexcept {
    return push(state, "", 0);
}
extern "C" __declspec(dllexport) int pc2_probe_binary(void* state) noexcept {
    constexpr char text[] = "Grüße\0PC2";
    return push(state, text, sizeof(text)-1);
}

extern "C" __declspec(dllexport) int pc2_poll(void* state) noexcept {
    if (!initialize()) return 0;
    char data[4096];
    DWORD size = 0;
    if (!pc2_diagnostic_inbox(data, sizeof(data), &size)) return 0;
    return push(state, data, size);
}
