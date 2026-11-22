// Original PC2Coop code, MIT. Diagnosis (FEAT-222, FEAT-223):
//  - pc2_system_line(): one log line about the PC (Windows, memory, game build, mod folders);
//  - pc2_write_report(): "Problembericht erstellen" - the newest logs of this mod folder in one
//    text file on the desktop, with Steam ids, lobby ids, the given player names and the
//    Windows user name replaced. Nothing is sent anywhere; the player decides what to share.
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <shlobj.h>
#include <knownfolders.h>
#include <algorithm>
#include <cstdio>
#include <cstring>
#include <map>
#include <string>
#include <utility>
#include <vector>

bool pc2_developer_mode() noexcept;

namespace {
constexpr ULONGLONG kHead = 256 * 1024;        // start of a long log (the header, the first session)
constexpr ULONGLONG kTail = 1280 * 1024;       // end of a long log (what happened last)
constexpr size_t kLogs = 3;                    // this run and the two before

std::wstring module_dir() {
    HMODULE self = nullptr;
    if (!GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                            reinterpret_cast<LPCWSTR>(&module_dir), &self)) return L"";
    std::vector<wchar_t> path(32768);
    DWORD size = GetModuleFileNameW(self, path.data(), static_cast<DWORD>(path.size()));
    if (!size || size >= path.size()) return L"";
    std::wstring text(path.data(), size);
    size_t slash = text.rfind(L'\\');
    return slash == std::wstring::npos ? L"" : text.substr(0, slash);
}

std::string narrow(const std::wstring& text) {
    if (text.empty()) return "";
    int size = WideCharToMultiByte(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), nullptr, 0, nullptr, nullptr);
    std::string out(size > 0 ? size : 0, '\0');
    if (size > 0) WideCharToMultiByte(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), out.data(), size, nullptr, nullptr);
    return out;
}

std::wstring widen(const std::string& text) {
    if (text.empty()) return L"";
    int size = MultiByteToWideChar(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), nullptr, 0);
    std::wstring out(size > 0 ? size : 0, L'\0');
    if (size > 0) MultiByteToWideChar(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), out.data(), size);
    return out;
}

std::string read_part(HANDLE file, ULONGLONG offset, ULONGLONG count) {
    std::string out(static_cast<size_t>(count), '\0');
    LARGE_INTEGER at;
    at.QuadPart = static_cast<LONGLONG>(offset);
    DWORD read = 0;
    if (!SetFilePointerEx(file, at, nullptr, FILE_BEGIN) || !ReadFile(file, out.data(), static_cast<DWORD>(count), &read, nullptr)) return "";
    out.resize(read);
    return out;
}

// A log that is still being written is opened for reading with full sharing.
std::string read_log(const std::wstring& path, ULONGLONG& skipped) {
    skipped = 0;
    HANDLE file = CreateFileW(path.c_str(), GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
                              nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (file == INVALID_HANDLE_VALUE) return "";
    LARGE_INTEGER size{};
    std::string out;
    if (GetFileSizeEx(file, &size)) {
        ULONGLONG total = static_cast<ULONGLONG>(size.QuadPart);
        if (total <= kHead + kTail) {
            out = read_part(file, 0, total);
        } else {
            std::string head = read_part(file, 0, kHead), tail = read_part(file, total - kTail, kTail);
            size_t end = head.rfind('\n');
            if (end != std::string::npos) head.resize(end + 1);
            size_t start = tail.find('\n');
            if (start != std::string::npos) tail.erase(0, start + 1);
            skipped = total - head.size() - tail.size();
            out = head + "\n[... " + std::to_string(skipped) + " bytes left out ...]\n\n" + tail;
        }
    }
    CloseHandle(file);
    return out;
}

bool digit(char c) { return c >= '0' && c <= '9'; }

class Anonymiser {
public:
    // pairs: "<steam id>=<name>" from Lua, this player first (P0).
    explicit Anonymiser(const std::vector<std::pair<std::string, std::string>>& pairs) {
        for (const auto& pair : pairs) {
            std::string label = label_for(pair.first, 'P');
            if (pair.second.size() >= 3) names_.emplace_back(pair.second, label);
        }
        // Longer names first, so "Vici2" is not half replaced by "Vici".
        std::sort(names_.begin(), names_.end(), [](const auto& a, const auto& b) { return a.first.size() > b.first.size(); });
    }

    std::string apply(const std::string& text) {
        std::string out;
        out.reserve(text.size());
        for (size_t i = 0; i < text.size();) {
            if (digit(text[i]) && (i == 0 || !digit(text[i - 1]))) {
                size_t end = i;
                while (end < text.size() && digit(text[end])) ++end;
                std::string number = text.substr(i, end - i);
                if (number.size() == 17 && number.compare(0, 7, "7656119") == 0) out += label_for(number, 'P');
                else if (number.size() == 18 && number.compare(0, 6, "109775") == 0) out += label_for(number, 'L');
                else out += number;
                i = end;
                continue;
            }
            out += text[i++];
        }
        for (const auto& name : names_) replace_all(out, name.first, name.second);
        hide_user_folders(out);
        return out;
    }

    std::string legend() const {
        return "P0 = whoever made this report; P1, P2, ... = other players; L1, ... = Steam lobbies.\n";
    }

private:
    std::string label_for(const std::string& id, char kind) {
        auto found = labels_.find(id);
        if (found != labels_.end()) return found->second;
        int& next = kind == 'P' ? players_ : lobbies_;
        std::string label = std::string(1, kind) + std::to_string(next++);
        labels_[id] = label;
        return label;
    }

    static void replace_all(std::string& text, const std::string& what, const std::string& with) {
        if (what.empty()) return;
        for (size_t at = text.find(what); at != std::string::npos; at = text.find(what, at + with.size()))
            text.replace(at, what.size(), with);
    }

    // "...\Users\<name>\..." -> "...\Users\<user>\..."
    static void hide_user_folders(std::string& text) {
        for (const char* marker : {"\\Users\\", "/Users/", "\\users\\"}) {
            size_t length = std::strlen(marker);
            for (size_t at = text.find(marker); at != std::string::npos; at = text.find(marker, at + length)) {
                size_t start = at + length, end = start;
                while (end < text.size() && text[end] != marker[length - 1] && text[end] != '\n' && text[end] != '|' && end - start < 64) ++end;
                if (end > start && end < text.size() && text[end] == marker[length - 1]) text.replace(start, end - start, "<user>");
            }
        }
    }

    std::map<std::string, std::string> labels_;
    std::vector<std::pair<std::string, std::string>> names_;
    int players_ = 0, lobbies_ = 1;
};

struct LogFile {
    std::wstring name;
    FILETIME written;
};

std::vector<LogFile> newest_logs(const std::wstring& dir) {
    std::vector<LogFile> logs;
    WIN32_FIND_DATAW data;
    HANDLE find = FindFirstFileW((dir + L"\\pc2coop-diagnostic-*.log").c_str(), &data);
    if (find == INVALID_HANDLE_VALUE) return logs;
    do {
        if (!(data.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY)) logs.push_back({data.cFileName, data.ftLastWriteTime});
    } while (FindNextFileW(find, &data));
    FindClose(find);
    std::sort(logs.begin(), logs.end(), [](const LogFile& a, const LogFile& b) { return CompareFileTime(&a.written, &b.written) > 0; });
    if (logs.size() > kLogs) logs.resize(kLogs);
    return logs;
}

std::string local_time(const FILETIME& time) {
    FILETIME local;
    SYSTEMTIME at;
    if (!FileTimeToLocalFileTime(&time, &local) || !FileTimeToSystemTime(&local, &at)) return "?";
    char text[32];
    sprintf_s(text, "%04u-%02u-%02u %02u:%02u", at.wYear, at.wMonth, at.wDay, at.wHour, at.wMinute);
    return text;
}

std::string windows_version() {
    using Get = LONG(WINAPI*)(OSVERSIONINFOW*);
    OSVERSIONINFOW info{};
    info.dwOSVersionInfoSize = sizeof(info);
    HMODULE ntdll = GetModuleHandleW(L"ntdll.dll");
    auto get = ntdll ? reinterpret_cast<Get>(reinterpret_cast<void*>(GetProcAddress(ntdll, "RtlGetVersion"))) : nullptr;
    if (!get || get(&info) != 0) return "?";
    return std::to_string(info.dwMajorVersion) + "." + std::to_string(info.dwMinorVersion) + "." + std::to_string(info.dwBuildNumber);
}

std::string file_version(const std::wstring& path) {
    DWORD ignored = 0, size = GetFileVersionInfoSizeW(path.c_str(), &ignored);
    if (!size) return "?";
    std::vector<unsigned char> data(size);
    VS_FIXEDFILEINFO* info = nullptr;
    UINT length = 0;
    if (!GetFileVersionInfoW(path.c_str(), 0, size, data.data())
        || !VerQueryValueW(data.data(), L"\\", reinterpret_cast<void**>(&info), &length) || !info) return "?";
    return std::to_string(HIWORD(info->dwFileVersionMS)) + "." + std::to_string(LOWORD(info->dwFileVersionMS)) + "."
        + std::to_string(HIWORD(info->dwFileVersionLS)) + "." + std::to_string(LOWORD(info->dwFileVersionLS));
}

// <library>\steamapps\common\<game>\PlanetCoaster2.exe -> buildid in steamapps\appmanifest_2688950.acf
// (searched a few folders up, so a copy of the game elsewhere just says "?").
std::string steam_build(const std::wstring& exe) {
    std::wstring dir = exe;
    std::string manifest;
    for (int up = 0; up < 5 && manifest.empty(); ++up) {
        size_t slash = dir.rfind(L'\\');
        if (slash == std::wstring::npos) return "?";
        dir.resize(slash);
        ULONGLONG skipped = 0;
        manifest = read_log(dir + L"\\appmanifest_2688950.acf", skipped);
    }
    size_t key = manifest.find("\"buildid\"");
    if (key == std::string::npos) return "?";
    size_t open = manifest.find('"', key + 9), close = open == std::string::npos ? open : manifest.find('"', open + 1);
    if (close == std::string::npos || close - open > 16) return "?";
    return manifest.substr(open + 1, close - open - 1);
}

std::string mod_folders(const std::wstring& ovldata) {
    std::vector<std::string> names;
    WIN32_FIND_DATAW data;
    HANDLE find = FindFirstFileW((ovldata + L"\\*").c_str(), &data);
    if (find == INVALID_HANDLE_VALUE) return "?";
    do {
        std::wstring name = data.cFileName;
        // Hidden helper folders (".pc2coop-alpha-backups") are no mods.
        if ((data.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) && !name.empty() && name[0] != L'.') names.push_back(narrow(name));
    } while (FindNextFileW(find, &data) && names.size() < 400);
    FindClose(find);
    std::sort(names.begin(), names.end());
    std::string out;
    for (const auto& name : names) out += (out.empty() ? "" : ",") + name;
    return out;
}
}

std::string pc2_system_line() {
    std::string line = "system|windows=" + windows_version();
    MEMORYSTATUSEX memory{};
    memory.dwLength = sizeof(memory);
    if (GlobalMemoryStatusEx(&memory)) line += "|ram-gb=" + std::to_string((memory.ullTotalPhys + (1ULL << 29)) >> 30);
    SYSTEM_INFO system{};
    GetSystemInfo(&system);
    line += "|cpus=" + std::to_string(system.dwNumberOfProcessors);
    std::vector<wchar_t> exe(32768);
    DWORD size = GetModuleFileNameW(nullptr, exe.data(), static_cast<DWORD>(exe.size()));
    if (size && size < exe.size()) {
        std::wstring path(exe.data(), size);
        line += "|game=" + file_version(path) + "|steam-build=" + steam_build(path);
    }
    std::wstring dir = module_dir();
    size_t slash = dir.rfind(L'\\');
    if (slash != std::wstring::npos) line += "|mods=" + mod_folders(dir.substr(0, slash));
    return line;
}

// args: "<lang>|<outdir>|<mod version>|<sid>=<name>|..." -> "report:done|<file>" or "report:error|<why>"
std::string pc2_write_report(const std::string& args) {
    std::vector<std::string> fields;
    for (size_t start = 0;;) {
        size_t bar = args.find('|', start);
        fields.push_back(args.substr(start, bar == std::string::npos ? std::string::npos : bar - start));
        if (bar == std::string::npos) break;
        start = bar + 1;
    }
    while (fields.size() < 3) fields.emplace_back();
    bool german = fields[0] == "de";
    std::vector<std::pair<std::string, std::string>> pairs;
    for (size_t i = 3; i < fields.size() && pairs.size() < 64; ++i) {
        size_t equals = fields[i].find('=');
        if (equals != std::string::npos && equals > 0) pairs.emplace_back(fields[i].substr(0, equals), fields[i].substr(equals + 1));
    }
    std::wstring dir = module_dir();
    std::vector<LogFile> logs = dir.empty() ? std::vector<LogFile>{} : newest_logs(dir);
    if (logs.empty()) return "report:error|logs";

    std::wstring target;
    if (!fields[1].empty() && pc2_developer_mode()) {
        target = widen(fields[1]);   // automated tests write into their own folder
    } else {
        PWSTR desktop = nullptr;
        if (FAILED(SHGetKnownFolderPath(FOLDERID_Desktop, 0, nullptr, &desktop)) || !desktop) {
            if (desktop) CoTaskMemFree(desktop);
            return "report:error|desktop";
        }
        target = desktop;
        CoTaskMemFree(desktop);
    }
    SYSTEMTIME now;
    GetLocalTime(&now);
    wchar_t stamp[32];
    swprintf_s(stamp, L"%04u-%02u-%02u-%02u%02u", now.wYear, now.wMonth, now.wDay, now.wHour, now.wMinute);
    std::wstring base = std::wstring(german ? L"PC2Coop-Bericht-" : L"PC2Coop-report-") + stamp;
    std::wstring name = base + L".txt";
    for (int n = 2; GetFileAttributesW((target + L"\\" + name).c_str()) != INVALID_FILE_ATTRIBUTES && n < 100; ++n)
        name = base + L"-" + std::to_wstring(n) + L".txt";

    Anonymiser anonymiser(pairs);
    std::string body, notable;
    int notable_count = 0;
    for (size_t i = 0; i < logs.size(); ++i) {
        ULONGLONG skipped = 0;
        std::string text = anonymiser.apply(read_log(dir + L"\\" + logs[i].name, skipped));
        body += "\n======== " + narrow(logs[i].name) + " | " + local_time(logs[i].written) + " | "
            + (i == 0 ? "newest" : "older") + " ========\n" + text;
        for (size_t start = 0; start < text.size() && notable_count < 40;) {
            size_t end = text.find('\n', start);
            if (end == std::string::npos) end = text.size();
            std::string line = text.substr(start, end - start);
            if (line.find("error|") != std::string::npos || line.find("exception|") != std::string::npos
                || line.find("-error") != std::string::npos || line.find("failed") != std::string::npos) {
                notable += "  " + line.substr(0, 400) + "\n";
                ++notable_count;
            }
            start = end + 1;
        }
    }
    std::string text = "\xEF\xBB\xBF";
    text += german ? "PC2Coop Problembericht\n" : "PC2Coop problem report\n";
    text += (german ? "Erstellt: " : "Created: ") + local_time([] { FILETIME f; GetSystemTimeAsFileTime(&f); return f; }())
        + " | PC2Coop " + fields[2] + " | Windows " + windows_version() + "\n";
    text += german
        ? "Enthält die neuesten Logs dieses PCs. Steam-IDs, Lobby-IDs, Spielernamen und der Windows-Benutzername sind ersetzt; Chat steht nie im Log.\n"
        : "Contains the newest logs of this PC. Steam IDs, lobby IDs, player names and the Windows user name are replaced; chat is never in the log.\n";
    text += anonymiser.legend();
    text += german ? "\nAuffällige Zeilen:\n" : "\nNotable lines:\n";
    text += notable.empty() ? (german ? "  keine\n" : "  none\n") : notable;
    text += body;

    std::wstring path = target + L"\\" + name;
    HANDLE file = CreateFileW(path.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_NEW, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (file == INVALID_HANDLE_VALUE) return "report:error|write";
    DWORD written = 0;
    bool ok = WriteFile(file, text.data(), static_cast<DWORD>(text.size()), &written, nullptr) && written == text.size();
    CloseHandle(file);
    if (!ok) { DeleteFileW(path.c_str()); return "report:error|write"; }
    return "report:done|" + narrow(name);
}
