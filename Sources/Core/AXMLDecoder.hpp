#ifndef KINW_AXML_DECODER_HPP
#define KINW_AXML_DECODER_HPP

#include <cstdint>
#include <cstddef>
#include <string>
#include <vector>
#include <map>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    char packageName[256];
    char versionName[128];
    char appLabel[256];
    char appIcon[256];
    char mainActivity[256];
    char screenOrientation[64];
    int versionCode;
    int isSuccess;
} KINWManifestInfo;

KINWManifestInfo kinw_parse_manifest(const uint8_t* data, size_t length);

#ifdef __cplusplus
}
#endif

#ifdef __cplusplus

namespace kinw {

struct ManifestMetadata {
    std::string packageName;
    std::string versionName;
    std::string appLabel;
    std::string appIcon;
    std::string mainActivity;
    std::string screenOrientation;
    int versionCode = 0;
    bool isValid = false;
};

class AXMLDecoder {
public:
    AXMLDecoder();
    ~AXMLDecoder();

    bool parse(const uint8_t* buffer, size_t size);
    std::string toXMLString() const;
    const ManifestMetadata& getMetadata() const { return metadata_; }

private:
    bool parseStringPool(const uint8_t* poolData, size_t poolSize);
    std::string getString(uint32_t index) const;

    std::vector<std::string> stringPool_;
    std::vector<uint32_t> resourceIds_;
    std::string xmlOutput_;
    ManifestMetadata metadata_;
};

} // namespace kinw

#endif // __cplusplus

#endif // KINW_AXML_DECODER_HPP
