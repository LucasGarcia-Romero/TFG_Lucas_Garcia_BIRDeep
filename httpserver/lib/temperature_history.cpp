#include "temperature_history.h"

#include <algorithm>
#include <cstdio>
#include <ctime>
#include <fstream>
#include <iomanip>
#include <limits>
#include <optional>
#include <sstream>
#include <string>
#include <vector>

struct SensorEntry {
    std::string timestamp;
    time_t ts = -1;
    std::optional<float> internalTemp;
    std::optional<float> externalTemp;
    std::optional<float> humidity;
};

static time_t parseTimestamp(const std::string& s) {
    struct tm t = {};
    if (sscanf(s.c_str(), "%4d-%2d-%2d %2d:%2d:%2d",
               &t.tm_year, &t.tm_mon, &t.tm_mday,
               &t.tm_hour, &t.tm_min, &t.tm_sec) == 6) {
        t.tm_year -= 1900;
        t.tm_mon  -= 1;
        t.tm_isdst = -1;
        return mktime(&t);
    }
    return -1;
}

static std::string urlDecode(const std::string& s) {
    std::string out;
    for (size_t i = 0; i < s.size(); ++i) {
        if (s[i] == '+') {
            out += ' ';
        } else if (s[i] == '%' && i + 2 < s.size()) {
            int val = 0;
            sscanf(s.substr(i + 1, 2).c_str(), "%2x", &val);
            out += static_cast<char>(val);
            i += 2;
        } else {
            out += s[i];
        }
    }
    return out;
}

static std::string getParam(const std::string& query, const std::string& key) {
    std::string search = key + "=";
    size_t pos = query.find(search);
    while (pos != std::string::npos) {
        if (pos == 0 || query[pos - 1] == '&') break;
        pos = query.find(search, pos + 1);
    }
    if (pos == std::string::npos) return "";

    pos += search.size();
    size_t end = query.find('&', pos);
    std::string raw = (end == std::string::npos) ? query.substr(pos) : query.substr(pos, end - pos);
    return urlDecode(raw);
}

static std::string jsonEscape(const std::string& s) {
    std::string out;
    for (char c : s) {
        if      (c == '"')  out += "\\\"";
        else if (c == '\\') out += "\\\\";
        else                out += c;
    }
    return out;
}

static std::vector<std::string> splitCsvLine(const std::string& line) {
    std::vector<std::string> parts;
    std::string part;
    std::stringstream ss(line);
    while (std::getline(ss, part, ',')) parts.push_back(part);
    return parts;
}

static std::optional<float> parseOptionalFloat(const std::string& raw) {
    if (raw.empty()) return std::nullopt;
    char* end = nullptr;
    float value = std::strtof(raw.c_str(), &end);
    if (end == raw.c_str()) return std::nullopt;
    return value;
}

static bool extractMetricFromTextLine(const std::string& line, const std::string& token, float& out) {
    size_t pos = line.find(token + "=");
    if (pos != std::string::npos) {
        pos += token.size() + 1;
        return sscanf(line.c_str() + pos, "%f", &out) == 1;
    }

    pos = line.find(token + " ");
    if (pos != std::string::npos) {
        pos += token.size() + 1;
        return sscanf(line.c_str() + pos, "%f", &out) == 1;
    }

    return false;
}

static std::optional<SensorEntry> parseSensorCsvLine(const std::string& line) {
    auto parts = splitCsvLine(line);
    if (parts.size() < 4) return std::nullopt;
    if (parts[0] == "timestamp") return std::nullopt;

    SensorEntry e;
    e.timestamp = parts[0];
    e.ts = parseTimestamp(e.timestamp);
    if (e.ts == -1) return std::nullopt;

    e.internalTemp = parseOptionalFloat(parts[1]);
    e.externalTemp = parseOptionalFloat(parts[2]);
    e.humidity     = parseOptionalFloat(parts[3]);
    return e;
}

static std::optional<SensorEntry> parseLegacyTextLine(const std::string& line) {
    if (line.size() < 19) return std::nullopt;

    SensorEntry e;
    e.timestamp = line.substr(0, 19);
    e.ts = parseTimestamp(e.timestamp);
    if (e.ts == -1) return std::nullopt;

    float value = 0.0f;
    if (extractMetricFromTextLine(line, "BOARD_TEMP", value))   e.internalTemp = value;
    if (extractMetricFromTextLine(line, "BOX_TEMP", value))     e.externalTemp = value;
    if (extractMetricFromTextLine(line, "BOX_HUMIDITY", value)) e.humidity = value;

    if (!e.internalTemp && !e.externalTemp && !e.humidity) return std::nullopt;
    return e;
}

static void readSensorCsv(const std::string& path, std::vector<SensorEntry>& entries) {
    std::ifstream file(path);
    if (!file.is_open()) return;

    std::string line;
    while (std::getline(file, line)) {
        auto entry = parseSensorCsvLine(line);
        if (entry) entries.push_back(*entry);
    }
}

static void readLegacyText(const std::string& path, std::vector<SensorEntry>& entries) {
    std::ifstream file(path);
    if (!file.is_open()) return;

    std::string line;
    while (std::getline(file, line)) {
        auto entry = parseLegacyTextLine(line);
        if (entry) entries.push_back(*entry);
    }
}

static std::vector<SensorEntry> loadEntries(const std::string& dataDir) {
    std::vector<SensorEntry> entries;

    // Formato nuevo, generado constantemente por stats/temp_monitor.sh
    readSensorCsv(dataDir + "/sensor_history.csv", entries);

    // Fallbacks para no perder históricos previos si todavía no existe el CSV nuevo.
    if (entries.empty()) {
        readLegacyText(dataDir + "/stats.txt", entries);
    }
    if (entries.empty()) {
        readLegacyText(dataDir + "/cpu_temp.txt", entries);
    }

    std::sort(entries.begin(), entries.end(), [](const SensorEntry& a, const SensorEntry& b) {
        return a.ts < b.ts;
    });
    return entries;
}

static void appendJsonNumberOrNull(std::ostringstream& json, const std::optional<float>& value) {
    if (value) json << std::fixed << std::setprecision(1) << *value;
    else       json << "null";
}

static void appendEntryJson(std::ostringstream& json, const SensorEntry& e) {
    json << "{\"timestamp\":\"" << jsonEscape(e.timestamp) << "\",";
    json << "\"internal_temp\":";
    appendJsonNumberOrNull(json, e.internalTemp);
    json << ",\"external_temp\":";
    appendJsonNumberOrNull(json, e.externalTemp);
    json << ",\"humidity\":";
    appendJsonNumberOrNull(json, e.humidity);
    json << "}";
}

std::string buildSensorHistoryJson(const std::string& queryString, const std::string& dataDir) {
    const std::string fromStr = getParam(queryString, "from");
    const std::string toStr   = getParam(queryString, "to");

    time_t now = time(nullptr);
    time_t fromTime = fromStr.empty() ? now - 24 * 60 * 60 : parseTimestamp(fromStr);
    time_t toTime   = toStr.empty()   ? now                : parseTimestamp(toStr);

    if (fromTime == -1) return R"({"error":"invalid 'from' parameter","entries":[]})";
    if (toTime == -1)   return R"({"error":"invalid 'to' parameter","entries":[]})";
    if (toTime < fromTime) return R"({"error":"'to' must be greater than 'from'","entries":[]})";

    std::vector<SensorEntry> entries = loadEntries(dataDir);

    std::ostringstream json;
    json << "{\"entries\":[";
    bool first = true;
    for (const auto& e : entries) {
        if (e.ts < fromTime) continue;
        if (e.ts > toTime) break;

        if (!first) json << ",";
        appendEntryJson(json, e);
        first = false;
    }
    json << "]}";
    return json.str();
}

std::string buildLatestSensorJson(const std::string& dataDir) {
    std::vector<SensorEntry> entries = loadEntries(dataDir);
    if (entries.empty()) {
        return R"({"timestamp":null,"internal_temp":null,"external_temp":null,"humidity":null,"cpu_temp":null})";
    }

    const SensorEntry& e = entries.back();
    std::ostringstream json;
    json << "{";
    json << "\"timestamp\":\"" << jsonEscape(e.timestamp) << "\",";
    json << "\"internal_temp\":";
    appendJsonNumberOrNull(json, e.internalTemp);
    json << ",\"external_temp\":";
    appendJsonNumberOrNull(json, e.externalTemp);
    json << ",\"humidity\":";
    appendJsonNumberOrNull(json, e.humidity);
    json << ",\"cpu_temp\":";
    appendJsonNumberOrNull(json, e.internalTemp);
    json << "}";
    return json.str();
}

std::string buildTemperatureHistoryJson(const std::string& queryString, const std::string& dataDir) {
    return buildSensorHistoryJson(queryString, dataDir);
}
