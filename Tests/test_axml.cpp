#include "../Sources/Core/AXMLDecoder.hpp"
#include <iostream>
#include <vector>
#include <cassert>
#include <fstream>

void test_empty_buffer() {
    kinw::AXMLDecoder decoder;
    bool res = decoder.parse(nullptr, 0);
    assert(!res);
    std::cout << "[PASS] test_empty_buffer\n";
}

void test_invalid_header() {
    uint8_t dummy[16] = {0x01, 0x00, 0x08, 0x00, 0x10, 0x00, 0x00, 0x00};
    kinw::AXMLDecoder decoder;
    bool res = decoder.parse(dummy, sizeof(dummy));
    assert(!res);
    std::cout << "[PASS] test_invalid_header\n";
}

int main(int argc, char** argv) {
    std::cout << "=== Running KINW AXMLDecoder Tests ===\n";
    test_empty_buffer();
    test_invalid_header();

    if (argc > 1) {
        std::ifstream file(argv[1], std::ios::binary);
        if (!file.is_open()) {
            std::cerr << "Could not open file: " << argv[1] << "\n";
            return 1;
        }
        std::vector<uint8_t> buffer((std::istreambuf_iterator<char>(file)), std::istreambuf_iterator<char>());
        KINWManifestInfo info = kinw_parse_manifest(buffer.data(), buffer.size());
        if (info.isSuccess) {
            std::cout << "[SUCCESS] Parsed manifest from " << argv[1] << "\n";
            std::cout << "Package: " << info.packageName << "\n";
            std::cout << "App Label: " << info.appLabel << "\n";
            std::cout << "Version: " << info.versionName << " (" << info.versionCode << ")\n";
            std::cout << "Main Activity: " << info.mainActivity << "\n";
            std::cout << "Orientation: " << info.screenOrientation << "\n";
        } else {
            std::cout << "[FAILED] Could not parse manifest from " << argv[1] << "\n";
        }
    }

    std::cout << "=== All Unit Tests Passed! ===\n";
    return 0;
}
