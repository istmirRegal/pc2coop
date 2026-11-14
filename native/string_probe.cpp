// Original MIT code. Calls the game's own string allocator, found by its code pattern
// (works across game builds as long as the routine itself is unchanged).
// No stock Lua layout writes, no engine calls on background threads.
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <cstdint>
#include <cstring>
void pc2_diagnostic_event(const char*) noexcept;
bool pc2_diagnostic_inbox(char*, DWORD, DWORD*) noexcept;

namespace {
using PushString = const char* (*)(void*, const char*, size_t);
PushString push_string = nullptr;
DWORD lua_thread = 0;
bool checked = false;
// Prologue of the routine (RVA 0x1e29f50 in build 26255360). -1 marks bytes that move
// between builds: RIP-relative displacements and a short jump distance.
constexpr int routine_pattern[] = {
    0x48,0x89,0x5c,0x24,0x10,0x57,0x48,0x83,0xec,0x20,0x8b,0x05,  -1,  -1,  -1,  -1,
    0x48,0x8b,0xf9,0xff,0xc0,0x89,0x05,  -1,  -1,  -1,  -1,0x89,0x41,0xf0,0x4d,0x85,
    0xc0,0x75,  -1,0x48,0x89,0x74,0x24,0x30,0x4c,0x8d,0x0d,  -1,  -1,  -1,  -1,0xb8,
    0xb3,0xcf,0x21,0x35,0x41,0x8b,0xf1,0x41,0xf7,0xe1,0x41,0x8b,0xc1,0x2b,0xc2,0xd1};
constexpr size_t pattern_size = sizeof(routine_pattern) / sizeof(routine_pattern[0]);

bool matches(const unsigned char* at) noexcept {
    for (size_t i = 0; i < pattern_size; ++i)
        if (routine_pattern[i] >= 0 && at[i] != static_cast<unsigned char>(routine_pattern[i])) return false;
    return true;
}

// Scans the executable sections of the game image. Exactly one match is required.
unsigned char* find_routine(unsigned char* base) noexcept {
    auto dos = reinterpret_cast<IMAGE_DOS_HEADER*>(base);
    if (dos->e_magic != IMAGE_DOS_SIGNATURE || dos->e_lfanew < 0 || dos->e_lfanew > 4096) return nullptr;
    auto pe = reinterpret_cast<IMAGE_NT_HEADERS64*>(base + dos->e_lfanew);
    if (pe->Signature != IMAGE_NT_SIGNATURE || pe->FileHeader.Machine != IMAGE_FILE_MACHINE_AMD64
        || pe->OptionalHeader.Magic != IMAGE_NT_OPTIONAL_HDR64_MAGIC) return nullptr;
    auto section = IMAGE_FIRST_SECTION(pe);
    unsigned char* found = nullptr;
    int count = 0;
    for (WORD i = 0; i < pe->FileHeader.NumberOfSections; ++i, ++section) {
        if (!(section->Characteristics & IMAGE_SCN_MEM_EXECUTE)) continue;
        DWORD size = section->Misc.VirtualSize;
        if (section->VirtualAddress >= pe->OptionalHeader.SizeOfImage || size < pattern_size) continue;
        if (size > pe->OptionalHeader.SizeOfImage - section->VirtualAddress) size = pe->OptionalHeader.SizeOfImage - section->VirtualAddress;
        unsigned char* start = base + section->VirtualAddress;
        for (DWORD offset = 0; offset + pattern_size <= size; offset += 16) {   // MSVC aligns functions to 16
            if (start[offset] == 0x48 && matches(start + offset)) {
                if (++count > 1) return nullptr;
                found = start + offset;
            }
        }
    }
    return count == 1 ? found : nullptr;
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
    pc2_diagnostic_event("native-stage:scan-begin");
    auto base = reinterpret_cast<unsigned char*>(GetModuleHandleW(nullptr));
    unsigned char* target = find_routine(base);
    if (!target || !region(target, pattern_size, false, true)) {
        pc2_diagnostic_event("native-stage:scan-rejected; game build not supported");
        return false;
    }
    char text[96];
    wsprintfA(text, "native-stage:code-matched; rva=0x%I64x",
              static_cast<unsigned long long>(target - base));
    pc2_diagnostic_event(text);
    push_string = reinterpret_cast<PushString>(target);
    lua_thread = GetCurrentThreadId();
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
