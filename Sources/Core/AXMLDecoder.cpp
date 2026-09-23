#include "AXMLDecoder.hpp"
#include <cstring>
#include <sstream>
#include <algorithm>

namespace kinw {

// Constants for Android Binary XML Chunks
constexpr uint16_t RES_NULL_TYPE = 0x0000;
constexpr uint16_t RES_STRING_POOL_TYPE = 0x0001;
constexpr uint16_t RES_TABLE_TYPE = 0x0002;
constexpr uint16_t RES_XML_TYPE = 0x0003;
constexpr uint16_t RES_XML_START_NAMESPACE_TYPE = 0x0100;
constexpr uint16_t RES_XML_END_NAMESPACE_TYPE = 0x0101;
constexpr uint16_t RES_XML_START_ELEMENT_TYPE = 0x0102;
constexpr uint16_t RES_XML_END_ELEMENT_TYPE = 0x0103;
constexpr uint16_t RES_XML_CDATA_TYPE = 0x0104;
constexpr uint16_t RES_XML_RESOURCE_MAP_TYPE = 0x0180;

constexpr uint32_t UTF8_FLAG = 1 << 8;

#pragma pack(push, 1)
struct ResChunkHeader {
    uint16_t type;
    uint16_t headerSize;
    uint32_t size;
};

struct ResStringPoolHeader {
    ResChunkHeader header;
    uint32_t stringCount;
    uint32_t styleCount;
    uint32_t flags;
    uint32_t stringsStart;
    uint32_t stylesStart;
};
#pragma pack(pop)

AXMLDecoder::AXMLDecoder() {}
AXMLDecoder::~AXMLDecoder() {}

std::string AXMLDecoder::getString(uint32_t index) const {
    if (index < stringPool_.size()) {
        return stringPool_[index];
    }
    return "";
}

bool AXMLDecoder::parseStringPool(const uint8_t* poolData, size_t poolSize) {
    if (poolSize < sizeof(ResStringPoolHeader)) return false;

    const auto* header = reinterpret_cast<const ResStringPoolHeader*>(poolData);
    uint32_t stringCount = header->stringCount;
    bool isUtf8 = (header->flags & UTF8_FLAG) != 0;

    const uint32_t* stringOffsets = reinterpret_cast<const uint32_t*>(poolData + header->header.headerSize);
    const uint8_t* stringsBase = poolData + header->stringsStart;

    stringPool_.clear();
    stringPool_.reserve(stringCount);

    for (uint32_t i = 0; i < stringCount; ++i) {
        uint32_t offset = stringOffsets[i];
        if (header->stringsStart + offset >= poolSize) {
            stringPool_.emplace_back("");
            continue;
        }

        const uint8_t* p = stringsBase + offset;
        std::string str;

        if (isUtf8) {
            // In UTF-8: first length is char count, second length is byte count
            uint32_t charCount = *p++;
            if (charCount & 0x80) {
                charCount = ((charCount & 0x7F) << 8) | *p++;
            }
            uint32_t byteCount = *p++;
            if (byteCount & 0x80) {
                byteCount = ((byteCount & 0x7F) << 8) | *p++;
            }
            if (p + byteCount <= poolData + poolSize) {
                str.assign(reinterpret_cast<const char*>(p), byteCount);
            }
        } else {
            // UTF-16LE
            uint32_t length = *reinterpret_cast<const uint16_t*>(p);
            p += 2;
            if (length & 0x8000) {
                uint32_t high = length & 0x7FFF;
                uint32_t low = *reinterpret_cast<const uint16_t*>(p);
                p += 2;
                length = (high << 16) | low;
            }

            // Simple conversion of ASCII characters from UTF-16LE
            const uint16_t* u16 = reinterpret_cast<const uint16_t*>(p);
            str.reserve(length);
            for (uint32_t c = 0; c < length && (reinterpret_cast<const uint8_t*>(u16 + c) < poolData + poolSize); ++c) {
                uint16_t ch = u16[c];
                if (ch < 0x80) {
                    str.push_back(static_cast<char>(ch));
                } else if (ch < 0x800) {
                    str.push_back(static_cast<char>(0xC0 | (ch >> 6)));
                    str.push_back(static_cast<char>(0x80 | (ch & 0x3F)));
                } else {
                    str.push_back(static_cast<char>(0xE0 | (ch >> 12)));
                    str.push_back(static_cast<char>(0x80 | ((ch >> 6) & 0x3F)));
                    str.push_back(static_cast<char>(0x80 | (ch & 0x3F)));
                }
            }
        }

        stringPool_.push_back(std::move(str));
    }

    return true;
}

bool AXMLDecoder::parse(const uint8_t* buffer, size_t size) {
    if (!buffer || size < 8) return false;

    metadata_ = ManifestMetadata();
    stringPool_.clear();
    resourceIds_.clear();

    const auto* rootHeader = reinterpret_cast<const ResChunkHeader*>(buffer);
    if (rootHeader->type != RES_XML_TYPE) {
        return false;
    }

    size_t offset = rootHeader->headerSize;
    std::ostringstream xml;
    xml << "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n";

    std::string currentActivity;

    while (offset + sizeof(ResChunkHeader) <= size) {
        const auto* chunk = reinterpret_cast<const ResChunkHeader*>(buffer + offset);
        if (chunk->size == 0 || offset + chunk->size > size) {
            break;
        }

        switch (chunk->type) {
            case RES_STRING_POOL_TYPE: {
                parseStringPool(buffer + offset, chunk->size);
                break;
            }
            case RES_XML_RESOURCE_MAP_TYPE: {
                size_t count = (chunk->size - chunk->headerSize) / sizeof(uint32_t);
                const uint32_t* ids = reinterpret_cast<const uint32_t*>(buffer + offset + chunk->headerSize);
                resourceIds_.assign(ids, ids + count);
                break;
            }
            case RES_XML_START_ELEMENT_TYPE: {
                if (offset + 36 <= size) {
                    const uint32_t* words = reinterpret_cast<const uint32_t*>(buffer + offset);
                    // words: [0] = header, [1] = header.size, [2] = lineNumber, [3] = comment,
                    // [4] = ns, [5] = name
                    uint32_t nameIdx = words[5];
                    std::string tagName = getString(nameIdx);

                    uint16_t attrStart = *reinterpret_cast<const uint16_t*>(buffer + offset + 24);
                    uint16_t attrSize = *reinterpret_cast<const uint16_t*>(buffer + offset + 26);
                    uint16_t attrCount = *reinterpret_cast<const uint16_t*>(buffer + offset + 28);

                    xml << "<" << tagName;

                    const uint8_t* attrPtr = buffer + offset + attrStart;
                    for (uint16_t i = 0; i < attrCount; ++i) {
                        if (attrPtr + 20 > buffer + size) break;

                        const uint32_t* attrWords = reinterpret_cast<const uint32_t*>(attrPtr);
                        std::string attrName = getString(attrWords[1]);
                        std::string attrRawValue = getString(attrWords[2]);

                        uint8_t dataType = *(attrPtr + 15);
                        uint32_t dataVal = *reinterpret_cast<const uint32_t*>(attrPtr + 16);

                        std::string attrValue = attrRawValue;
                        if (attrValue.empty()) {
                            if (dataType == 0x10) { // TYPE_INT_DEC
                                attrValue = std::to_string(static_cast<int32_t>(dataVal));
                            } else if (dataType == 0x11) { // TYPE_INT_HEX
                                char hexBuf[32];
                                snprintf(hexBuf, sizeof(hexBuf), "0x%x", dataVal);
                                attrValue = hexBuf;
                            } else if (dataType == 0x12) { // TYPE_INT_BOOLEAN
                                attrValue = (dataVal != 0) ? "true" : "false";
                            } else if (dataType == 0x01) { // TYPE_REFERENCE
                                char refBuf[32];
                                snprintf(refBuf, sizeof(refBuf), "@0x%08x", dataVal);
                                attrValue = refBuf;
                            }
                        }

                        xml << " " << attrName << "=\"" << attrValue << "\"";

                        // Extract metadata
                        if (tagName == "manifest") {
                            if (attrName == "package") {
                                metadata_.packageName = attrValue;
                            } else if (attrName == "versionName") {
                                metadata_.versionName = attrValue;
                            } else if (attrName == "versionCode") {
                                metadata_.versionCode = std::atoi(attrValue.c_str());
                            }
                        } else if (tagName == "application") {
                            if (attrName == "label") {
                                metadata_.appLabel = attrValue;
                            } else if (attrName == "icon") {
                                metadata_.appIcon = attrValue;
                            }
                        } else if (tagName == "activity") {
                            if (attrName == "name") {
                                currentActivity = attrValue;
                            } else if (attrName == "screenOrientation") {
                                if (metadata_.screenOrientation.empty()) {
                                    metadata_.screenOrientation = attrValue;
                                }
                            }
                        } else if (tagName == "action") {
                            if (attrName == "name" && attrValue == "android.intent.action.MAIN") {
                                if (!currentActivity.empty()) {
                                    metadata_.mainActivity = currentActivity;
                                }
                            }
                        }

                        attrPtr += attrSize > 0 ? attrSize : 20;
                    }

                    xml << ">\n";
                }
                break;
            }
            case RES_XML_END_ELEMENT_TYPE: {
                if (offset + 24 <= size) {
                    const uint32_t* words = reinterpret_cast<const uint32_t*>(buffer + offset);
                    std::string tagName = getString(words[5]);
                    xml << "</" << tagName << ">\n";
                    if (tagName == "activity") {
                        currentActivity.clear();
                    }
                }
                break;
            }
            default:
                break;
        }

        offset += chunk->size;
    }

    xmlOutput_ = xml.str();
    metadata_.isValid = !metadata_.packageName.empty();

    if (metadata_.appLabel.empty()) {
        metadata_.appLabel = metadata_.packageName;
    }

    return metadata_.isValid;
}

std::string AXMLDecoder::toXMLString() const {
    return xmlOutput_;
}

} // namespace kinw

extern "C" {

KINWManifestInfo kinw_parse_manifest(const uint8_t* data, size_t length) {
    KINWManifestInfo info;
    std::memset(&info, 0, sizeof(info));

    kinw::AXMLDecoder decoder;
    if (decoder.parse(data, length)) {
        const auto& meta = decoder.getMetadata();
        std::strncpy(info.packageName, meta.packageName.c_str(), sizeof(info.packageName) - 1);
        std::strncpy(info.versionName, meta.versionName.c_str(), sizeof(info.versionName) - 1);
        std::strncpy(info.appLabel, meta.appLabel.c_str(), sizeof(info.appLabel) - 1);
        std::strncpy(info.appIcon, meta.appIcon.c_str(), sizeof(info.appIcon) - 1);
        std::strncpy(info.mainActivity, meta.mainActivity.c_str(), sizeof(info.mainActivity) - 1);
        std::strncpy(info.screenOrientation, meta.screenOrientation.c_str(), sizeof(info.screenOrientation) - 1);
        info.versionCode = meta.versionCode;
        info.isSuccess = 1;
    } else {
        info.isSuccess = 0;
    }

    return info;
}

}
