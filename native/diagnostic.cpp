// Original PC2Coop code, MIT. Zero-result Lua callbacks: no Lua ABI access.
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <cstdio>
#include <cstring>
#include <string>

std::string pc2_system_line();

namespace {
HMODULE module_handle = nullptr;
SRWLOCK file_lock = SRWLOCK_INIT;
HANDLE log_file = INVALID_HANDLE_VALUE;
unsigned long bytes_written = 0;
constexpr unsigned long file_limit = 4 * 1024 * 1024;
struct Record {
    char bytes[4096];
    unsigned int size = 0;
    int high = -1;
    bool active = false;
    bool overflow = false;
};
thread_local Record record;

// Crash note (FEAT-222): the first few fatal exceptions of this game run go into the log
// before the game's own handler runs. First chance - the game may still handle one.
ULONG_PTR exe_base = 0, exe_end = 0, own_base = 0, own_end = 0;

void image_range(HMODULE module, ULONG_PTR& base, ULONG_PTR& end) noexcept {
    base = end = reinterpret_cast<ULONG_PTR>(module);
    if (!module) return;
    auto dos = reinterpret_cast<const IMAGE_DOS_HEADER*>(module);
    if (dos->e_magic != IMAGE_DOS_SIGNATURE) return;
    auto nt = reinterpret_cast<const IMAGE_NT_HEADERS*>(reinterpret_cast<const char*>(module) + dos->e_lfanew);
    if (nt->Signature == IMAGE_NT_SIGNATURE) end = base + nt->OptionalHeader.SizeOfImage;
}

LONG CALLBACK crash_watch(EXCEPTION_POINTERS* info) noexcept {
    static volatile LONG written = 0;
    DWORD code = info && info->ExceptionRecord ? info->ExceptionRecord->ExceptionCode : 0;
    switch (code) {
    case EXCEPTION_ACCESS_VIOLATION: case EXCEPTION_STACK_OVERFLOW: case EXCEPTION_ILLEGAL_INSTRUCTION:
    case EXCEPTION_INT_DIVIDE_BY_ZERO: case EXCEPTION_PRIV_INSTRUCTION:
    case 0xC0000374:   // heap corruption
    case 0xC0000409:   // fail fast / stack buffer overrun
        break;
    default:
        return EXCEPTION_CONTINUE_SEARCH;
    }
    if (InterlockedIncrement(&written) > 8) return EXCEPTION_CONTINUE_SEARCH;
    ULONG_PTR at = reinterpret_cast<ULONG_PTR>(info->ExceptionRecord->ExceptionAddress);
    const char* where = "other";
    ULONG_PTR offset = at;
    if (at >= exe_base && at < exe_end) { where = "game"; offset = at - exe_base; }
    else if (at >= own_base && at < own_end) { where = "PC2CoopDiagnostic.dll"; offset = at - own_base; }
    char line[256];
    int size = sprintf_s(line, "exception|code=0x%08lX|in=%s+0x%llX|thread=%lu|first-chance (the game may still handle it)\n",
                         static_cast<unsigned long>(code), where, static_cast<unsigned long long>(offset), GetCurrentThreadId());
    // Never wait here: the crashing thread may hold the lock itself.
    if (size > 0 && TryAcquireSRWLockExclusive(&file_lock)) {
        DWORD done = 0;
        if (log_file != INVALID_HANDLE_VALUE) WriteFile(log_file, line, static_cast<DWORD>(size), &done, nullptr);
        ReleaseSRWLockExclusive(&file_lock);
    }
    return EXCEPTION_CONTINUE_SEARCH;
}

void append(const char* bytes, DWORD size) noexcept {
    AcquireSRWLockExclusive(&file_lock);
    if (log_file != INVALID_HANDLE_VALUE && bytes_written + size <= file_limit) {
        DWORD written = 0;
        if (WriteFile(log_file, bytes, size, &written, nullptr)) bytes_written += written;
    }
    ReleaseSRWLockExclusive(&file_lock);
}

int nibble(unsigned int value) noexcept {
    if (!record.active || record.overflow) return 0;
    if (record.high < 0) {
        record.high = static_cast<int>(value);
    } else if (record.size < sizeof(record.bytes)) {
        record.bytes[record.size++] = static_cast<char>((record.high << 4) | value);
        record.high = -1;
    } else {
        record.overflow = true;
    }
    return 0;
}
}

void pc2_net_command(const char* bytes, unsigned int size) noexcept;

void pc2_diagnostic_event(const char* message) noexcept {
    append(message, static_cast<DWORD>(std::strlen(message)));
    append("\n", 1);
}

// The developer command channel (a file dropped next to the DLL) exists for automated
// tests only. Players' installations do not have the marker file, so there it is off.
static bool developer_mode() noexcept {
    static int state = -1;
    if (state < 0) {
        wchar_t path[2048];
        DWORD length = GetModuleFileNameW(module_handle, path, 2048);
        wchar_t* slash = length && length < 2048 ? wcsrchr(path, L'\\') : nullptr;
        state = slash && wcscpy_s(slash + 1, 2048 - (slash + 1 - path), L"pc2coop-dev.flag") == 0
            && GetFileAttributesW(path) != INVALID_FILE_ATTRIBUTES ? 1 : 0;
    }
    return state == 1;
}

// F8 (developer dialog) is reported only with the marker file (TP-31: players never see it).
bool pc2_developer_mode() noexcept { return developer_mode(); }

bool pc2_diagnostic_inbox(char* data, DWORD capacity, DWORD* size) noexcept {
    static FILETIME last_write{};
    static DWORD last_size = 0;
    if (!developer_mode()) return false;
    wchar_t path[2048];
    DWORD length = GetModuleFileNameW(module_handle, path, 2048);
    if (!length || length >= 2048) return false;
    wchar_t* slash = wcsrchr(path, L'\\');
    if (!slash || swprintf_s(slash+1, 2048-(slash+1-path),
            L"pc2coop-inbox-%lu.txt", GetCurrentProcessId()) <= 0) return false;
    HANDLE file = CreateFileW(path, GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
                             nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (file == INVALID_HANDLE_VALUE) return false;
    BY_HANDLE_FILE_INFORMATION info{};
    bool ok = GetFileInformationByHandle(file, &info) && !info.nFileSizeHigh
        && info.nFileSizeLow > 0 && info.nFileSizeLow <= capacity;
    if (ok && CompareFileTime(&last_write, &info.ftLastWriteTime) == 0 && last_size == info.nFileSizeLow) ok = false;
    if (ok) ok = ReadFile(file, data, capacity, size, nullptr) && *size == info.nFileSizeLow;
    if (ok) { last_write = info.ftLastWriteTime; last_size = info.nFileSizeLow; }
    CloseHandle(file);
    return ok;
}

BOOL WINAPI DllMain(HINSTANCE instance, DWORD reason, LPVOID reserved) {
    if (reason == DLL_PROCESS_ATTACH) module_handle = instance;
    // Unloaded while the game still runs would mean a crash (see pc2_bootstrap). The line tells
    // a report which way the DLL went; no lock wait in the loader lock.
    if (reason == DLL_PROCESS_DETACH && TryAcquireSRWLockExclusive(&file_lock)) {
        const char* line = reserved ? "dll:detach|process-exit\n" : "dll:detach|unloaded-while-running\n";
        DWORD done = 0;
        if (log_file != INVALID_HANDLE_VALUE) WriteFile(log_file, line, static_cast<DWORD>(strlen(line)), &done, nullptr);
        ReleaseSRWLockExclusive(&file_lock);
    }
    return TRUE;
}

extern "C" __declspec(dllexport) int pc2_bootstrap(void*) noexcept {
    // Called by Lua after LoadLibrary has finished; no work in the loader lock.
    AcquireSRWLockExclusive(&file_lock);
    if (log_file == INVALID_HANDLE_VALUE) {
        wchar_t path[32768];
        DWORD size = GetModuleFileNameW(module_handle, path, 32768);
        if (size && size < 32768) {
            wchar_t* slash = wcsrchr(path, L'\\');
            if (slash && swprintf_s(slash + 1, 32768 - (slash + 1 - path),
                    L"pc2coop-diagnostic-%lu.log", GetCurrentProcessId()) > 0) {
                log_file = CreateFileW(path, GENERIC_WRITE, FILE_SHARE_READ, nullptr,
                                      CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
            }
        }
    }
    ReleaseSRWLockExclusive(&file_lock);
    char header[128];
    int size = sprintf_s(header, "PC2COOP diagnostic=1 pid=%lu thread=%lu no-lua-abi=1\n",
                         GetCurrentProcessId(), GetCurrentThreadId());
    if (size > 0) append(header, static_cast<DWORD>(size));
    static bool once = false;
    if (!once) {
        once = true;
        try {
            std::string system = pc2_system_line() + "\n";
            append(system.data(), static_cast<DWORD>(system.size()));
        } catch (...) {}
        image_range(GetModuleHandleW(nullptr), exe_base, exe_end);
        image_range(module_handle, own_base, own_end);
        // Crash on quitting (owner, every version): Lua frees the DLL when the game closes its Lua
        // states (package.loadlib -> FreeLibrary), but Steam still holds our callback objects and
        // Windows our exception handler - both would then point into unmapped code. Pinned, the
        // DLL stays until the process ends.
        HMODULE pinned = nullptr;
        bool pin = GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_PIN,
                                      reinterpret_cast<LPCWSTR>(&crash_watch), &pinned) != FALSE;
        append(pin ? "dll:pinned\n" : "dll:pin-failed\n", pin ? 11 : 15);
        AddVectoredExceptionHandler(0, crash_watch);
    }
    return 0;
}

extern "C" __declspec(dllexport) int pc2_log_begin(void*) noexcept {
    record = Record{};
    record.active = true;
    return 0;
}

extern "C" __declspec(dllexport) int pc2_log_end(void*) noexcept {
    if (record.active) {
        if (record.overflow || record.high >= 0) {
            constexpr char rejected[] = "[diagnostic record rejected]\n";
            append(rejected, sizeof(rejected) - 1);
        } else {
            append(record.bytes, record.size);
            append("\n", 1);
        }
    }
    record.active = false;
    return 0;
}

// Same nibble record as the log, but handed to the Steam transport as one command.
extern "C" __declspec(dllexport) int pc2_net_end(void*) noexcept {
    if (record.active && !record.overflow && record.high < 0) pc2_net_command(record.bytes, record.size);
    record.active = false;
    return 0;
}

#define NIBBLE(name, value) extern "C" __declspec(dllexport) int pc2_nibble_##name(void*) noexcept { return nibble(value); }
NIBBLE(0, 0) NIBBLE(1, 1) NIBBLE(2, 2) NIBBLE(3, 3)
NIBBLE(4, 4) NIBBLE(5, 5) NIBBLE(6, 6) NIBBLE(7, 7)
NIBBLE(8, 8) NIBBLE(9, 9) NIBBLE(a, 10) NIBBLE(b, 11)
NIBBLE(c, 12) NIBBLE(d, 13) NIBBLE(e, 14) NIBBLE(f, 15)
