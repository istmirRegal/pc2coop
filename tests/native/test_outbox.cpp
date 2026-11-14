// Outbox test: the real steam_net.cpp against a fake Steam whose reliable send buffer
// fills up (k_EResultLimitExceeded = 25) and drains a little every tick, like a slow link.
// Built and run by tests/test_native_outbox.py. Exit code 0 = pass.
#include "../../native/steam_net.cpp"
#include <cstdlib>
#include <fstream>
#include <iterator>

void pc2_diagnostic_event(const char*) noexcept {}
int pc2_push_string(void*, const char*, size_t) noexcept { return 0; }

namespace fake {
constexpr size_t kCapacity = 600 * 1024;   // bytes Steam accepts before saying 25
constexpr size_t kDrain = 200 * 1024;      // bytes delivered per tick
struct Sent { unsigned long long to; std::string data; };
std::deque<Sent> wire;
size_t buffered = 0;
int refused = 0;
std::vector<std::string> delivered;        // non-file payloads in arrival order

void* messages() { return reinterpret_cast<void*>(1); }
void set_id(Identity* identity, unsigned long long id) { std::memset(identity, 0, sizeof(*identity)); std::memcpy(identity->data, &id, sizeof(id)); }
unsigned long long get_id(const Identity* identity) { unsigned long long id; std::memcpy(&id, identity->data, sizeof(id)); return id; }
int send(void*, const Identity* peer, const void* data, unsigned int size, int, int) {
    if (buffered + size > kCapacity) { ++refused; return 25; }
    buffered += size;
    wire.push_back(Sent{get_id(peer), std::string(static_cast<const char*>(data), size)});
    return 1;
}
void tick() {
    size_t budget = kDrain;
    while (!wire.empty() && budget > 0) {
        Sent message = wire.front();
        wire.pop_front();
        budget -= message.data.size() < budget ? message.data.size() : budget;
        buffered -= message.data.size();
        if (message.data[0] == '\x02') receive_chunk(1111, message.data.data(), message.data.size());
        else delivered.push_back(message.data);
    }
}
}

std::string read_all(const std::wstring& path) {
    std::ifstream in(path.c_str(), std::ios::binary);
    return std::string(std::istreambuf_iterator<char>(in), std::istreambuf_iterator<char>());
}

int fail(const char* why) { std::printf("FAIL: %s\n", why); return 1; }

int main() {
    api.Messages = fake::messages;
    api.SetSteamID64 = fake::set_id;
    api.GetSteamID64 = fake::get_id;
    api.SendMessageToUser = fake::send;

    // A park-sized file (7.5 MB) of varied bytes.
    std::string park(7500000, '\0');
    unsigned int seed = 12345;
    for (char& c : park) { seed = seed * 1103515245u + 12345u; c = static_cast<char>(seed >> 16); }
    { std::ofstream out(game_path("pc2coop-host-test.bin").c_str(), std::ios::binary); out.write(park.data(), static_cast<std::streamsize>(park.size())); }
    DeleteFileW(game_path("pc2coop-join-test.bin").c_str());

    send_to(2222, "hello-before", 12);
    send_file(2222, "pc2coop-host-test.bin", "pc2coop-join-test.bin");
    send_to(2222, "park|after-file", 15);       // must arrive after every chunk
    for (int i = 0; i < 20000 && (!outbox_for(2222).items.empty() || !fake::wire.empty()); ++i) {
        pump_outbox();
        fake::tick();
    }
    bool sent = false, done = false, stalled = false;
    for (const std::string& event : events) {
        sent = sent || event.rfind("file:sent|2222|pc2coop-join-test.bin|7500000", 0) == 0;
        done = done || event.rfind("file:done|1111|pc2coop-join-test.bin|7500000", 0) == 0;
        stalled = stalled || event.rfind("net:peer-stalled", 0) == 0;
    }
    std::printf("refused=%d delivered=%zu sent=%d done=%d\n", fake::refused, fake::delivered.size(), sent, done);
    if (fake::refused == 0) return fail("fake Steam never refused; test does not cover the limit");
    if (stalled) return fail("peer reported stalled");
    if (!sent || !done) return fail("file not reported complete");
    if (read_all(game_path("pc2coop-join-test.bin")) != park) return fail("received file differs");
    if (fake::delivered.size() != 2 || fake::delivered[0] != "hello-before" || fake::delivered[1] != "park|after-file")
        return fail("messages lost or out of order");
    DeleteFileW(game_path("pc2coop-host-test.bin").c_str());
    DeleteFileW(game_path("pc2coop-join-test.bin").c_str());

    // While the joiner loads the park, late chunks must not rewrite its files.
    remember("phase", "loading");
    std::string late = std::string("\x02pc2coop-join-test.bin|10|0|") + "0123456789";
    receive_chunk(1111, late.data(), late.size());
    if (GetFileAttributesW(game_path("pc2coop-join-test.bin").c_str()) != INVALID_FILE_ATTRIBUTES)
        return fail("file rewritten while loading");
    remember("phase", "awaiting");
    receive_chunk(1111, late.data(), late.size());
    if (read_all(game_path("pc2coop-join-test.bin")) != "0123456789") return fail("chunk refused although not loading");
    DeleteFileW(game_path("pc2coop-join-test.bin").c_str());
    std::printf("PASS\n");
    return 0;
}
