// Expone las rutas privadas, cada una de ellas con su clase + funcion exec
#include "PostMethod.h"
#include "System.h"
#include "Json.hpp"

#include <openssl/sha.h>
#include <algorithm>
#include <cmath>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <map>
#include <sstream>
#include <system_error>
#include <thread>
#include <vector>

static const double AUTO_CLEANUP_THRESHOLD_PERCENT = 90.0;
static const double AUTO_CLEANUP_DELETE_PERCENT = 0.20;
static const char* AUTO_CLEANUP_FILE = "auto_cleanup.txt";

// funcion para el hasheo de la contrasena por medio de sha256
static std::string sha256(const std::string& input)
{
    unsigned char hash[SHA256_DIGEST_LENGTH];
    SHA256(reinterpret_cast<const unsigned char*>(input.c_str()), input.size(), hash);
    std::ostringstream oss;
    for (int i = 0; i < SHA256_DIGEST_LENGTH; i++)
        oss << std::hex << std::setw(2) << std::setfill('0') << (int)hash[i];
    return oss.str();
}

static std::string escapeJson(const std::string& s)
{
    std::string out;
    for (char c : s) {
        switch (c) {
        case '"': out += "\\\""; break;
        case '\\': out += "\\\\"; break;
        case '\b': out += "\\b"; break;
        case '\f': out += "\\f"; break;
        case '\n': out += "\\n"; break;
        case '\r': out += "\\r"; break;
        case '\t': out += "\\t"; break;
        default: out += c; break;
        }
    }
    return out;
}

static bool hasExtension(const std::filesystem::path& path, const std::string& extension)
{
    return path.has_extension() && path.extension() == extension;
}

static uintmax_t removeFilesWithExtension(const std::filesystem::path& root, const std::string& extension)
{
    std::error_code ec;
    if (!std::filesystem::exists(root, ec)) return 0;

    uintmax_t removed = 0;
    for (const auto& entry : std::filesystem::recursive_directory_iterator(root, std::filesystem::directory_options::skip_permission_denied, ec)) {
        if (ec) break;
        if (!entry.is_regular_file(ec)) continue;
        if (!hasExtension(entry.path(), extension)) continue;

        std::error_code removeEc;
        if (std::filesystem::remove(entry.path(), removeEc)) removed++;
    }

    return removed;
}

static void writeSensorCsvHeader(const std::filesystem::path& filePath)
{
    std::ofstream file(filePath, std::ios::trunc);
    file << "timestamp,internal_temp,external_temp,humidity\n";
}

static std::filesystem::path autoCleanupConfigPath()
{
    return std::filesystem::path(System::dataFilesFolder) / AUTO_CLEANUP_FILE;
}

static bool autoCleanupEnabled()
{
    std::ifstream file(autoCleanupConfigPath());
    std::string value;
    std::getline(file, value);
    return value == "1" || value == "true" || value == "on";
}

static bool writeAutoCleanupEnabled(bool enabled)
{
    std::ofstream file(autoCleanupConfigPath(), std::ios::trunc);
    if (!file.is_open()) return false;
    file << (enabled ? "1" : "0") << "\n";
    return true;
}

static uintmax_t removeOldestPercent(const std::filesystem::path& root, const std::string& extension, double percent)
{
    std::error_code ec;
    if (!std::filesystem::exists(root, ec)) return 0;

    std::vector<std::filesystem::directory_entry> files;
    for (const auto& entry : std::filesystem::recursive_directory_iterator(root, std::filesystem::directory_options::skip_permission_denied, ec)) {
        if (ec) break;
        if (!entry.is_regular_file(ec)) continue;
        if (!hasExtension(entry.path(), extension)) continue;
        files.push_back(entry);
    }

    if (files.empty()) return 0;

    std::sort(files.begin(), files.end(), [](const auto& a, const auto& b) {
        std::error_code ecA;
        std::error_code ecB;
        return a.last_write_time(ecA) < b.last_write_time(ecB);
    });

    size_t toRemove = static_cast<size_t>(std::ceil(files.size() * percent));
    if (toRemove == 0) toRemove = 1;

    uintmax_t removed = 0;
    for (size_t i = 0; i < toRemove && i < files.size(); ++i) {
        std::error_code removeEc;
        if (std::filesystem::remove(files[i].path(), removeEc)) removed++;
    }

    return removed;
}

static uintmax_t trimCsvOldestPercent(const std::filesystem::path& filePath, double percent)
{
    std::ifstream in(filePath);
    if (!in.is_open()) return 0;

    std::vector<std::string> lines;
    std::string line;
    while (std::getline(in, line)) {
        lines.push_back(line);
    }
    in.close();

    if (lines.size() <= 1) return 0;

    size_t dataLines = lines.size() - 1;
    size_t toRemove = static_cast<size_t>(std::ceil(dataLines * percent));
    if (toRemove == 0) toRemove = 1;
    if (toRemove > dataLines) toRemove = dataLines;

    std::ofstream out(filePath, std::ios::trunc);
    if (!out.is_open()) return 0;

    out << lines[0] << "\n";
    for (size_t i = 1 + toRemove; i < lines.size(); ++i) {
        out << lines[i] << "\n";
    }

    return static_cast<uintmax_t>(toRemove);
}

struct AutoCleanupResult {
    bool ran = false;
    uintmax_t wavRemoved = 0;
    uintmax_t pngRemoved = 0;
    uintmax_t csvRowsRemoved = 0;
};

static AutoCleanupResult runAutoCleanupIfNeeded(double usedPercent)
{
    AutoCleanupResult result;

    if (!autoCleanupEnabled() || usedPercent <= AUTO_CLEANUP_THRESHOLD_PERCENT) {
        return result;
    }

    result.ran = true;
    std::filesystem::path recordings = std::filesystem::path(System::dataFilesFolder) / "recordings";
    result.wavRemoved = removeOldestPercent(recordings, ".wav", AUTO_CLEANUP_DELETE_PERCENT);
    result.pngRemoved = removeOldestPercent(recordings, ".png", AUTO_CLEANUP_DELETE_PERCENT);

    std::filesystem::path sensorCsv = std::filesystem::path(System::dataFilesFolder) / "sensor_history.csv";
    result.csvRowsRemoved = trimCsvOldestPercent(sensorCsv, AUTO_CLEANUP_DELETE_PERCENT);

    return result;
}

string Login::exec(string params)
{
    string user = getPostParam(params, "user");
    string password = getPostParam(params, "pass");
    string passHash = sha256(password);

    std::ifstream file(System::dataFilesFolder + "/credentials.txt");
    if (!file.is_open())
        return "{\"ok\":false,\"error\":\"no credentials file\"}";

    std::string line;
    while (std::getline(file, line))
    {
        size_t sep = line.find(':');
        if (sep == std::string::npos) continue;

        string fileUser = line.substr(0, sep);
        string fileHash = line.substr(sep + 1);

        if (fileUser == user && fileHash == passHash)
            return "{\"ok\":true}";
    }

    return "{\"ok\":false}";
}

string ListWavFiles::exec(string params)
{
    return string();
}

//--- helper function convert timepoint to usable timestamp
template <typename TP>
time_t to_time_t(TP tp) {
    using namespace std::chrono;
    auto sctp = time_point_cast<system_clock::duration>(tp - TP::clock::now() + system_clock::now());
    return system_clock::to_time_t(sctp);
}

string ListFiles::exec(string params)
{
    std::string path = getPostParam(params, "directory");
    replaceSubstrs(path, "/../", "/"); // avoid relative paths
    replaceSubstrs(path, "//", "/"); // avoid relative paths

    int parentIdx = (int)path.find_last_of("/", path.length() - 2);
    string parentPath = path;
    if (parentIdx != string::npos)
        parentPath = path.substr(0, parentIdx + 1);

    std::string realPath = System::dataFilesFolder + "/" + path;
    std::string directories = "{\"files\": [";
    std::map<time_t, std::vector<std::filesystem::directory_entry>, std::greater<time_t>> sort_by_time;

    int countFiles = 0;
    for (const auto& entry : std::filesystem::directory_iterator(realPath))
    {
        auto time = to_time_t(entry.last_write_time());
        sort_by_time[time].push_back(entry);
    }

    // add previous folder
    directories += "\n{\n"
        "\"parent\":\"" + parentPath + "\",\n"
        "\"name\":\"\",\n"
        "\"date\":\"\",\n"
        "\"type\":\"PARENTDIR\"\n"
        "}\n,";

    for (auto const& [time, entryList] : sort_by_time)
    {
        for (auto entry : entryList) {
            std::string href;
            std::string name = (char*)entry.path().filename().u8string().c_str();
            string folderDate = std::string(asctime(std::localtime(&time)));
            folderDate.pop_back(); // scape last \n
            if (entry.is_directory())
            {
                href = name + "/";
                directories += "\n{\n"
                    "\"parent\":\"" + parentPath + "\",\n"
                    "\"name\":\"" + href + "\",\n"
                    "\"date\":\"" + folderDate + "\",\n"
                    "\"type\":\"DIR\"\n"
                    "}\n,";
            }

            if (entry.is_regular_file()) {
                href = name;
                directories += "\n{\n"
                    "\"parent\":\"" + parentPath + "\",\n"
                    "\"name\":\"" + href + "\",\n"
                    "\"date\":\"" + folderDate + "\",\n"
                    "\"type\":\"FILE\"\n"
                    "}\n,";
            }
            countFiles++;
        }
    }
    directories.pop_back();
    directories += "]}";
    return directories;
}

string RecordData::exec(string params)
{
    json::JSON obj = json::JSON::Load(params);
    std::ofstream outfile;
    outfile.open(obj["fileName"].ToString(), std::ios_base::app);
    for (auto& val : *(obj.Internal.Map))
        outfile << val.second << "\t";
    outfile << "\n";
    outfile.close();
    return "OK";
}

string GetConfig::exec(string params)
{
    std::map<std::string, std::string> defaults = {
        {"STATION", "TECHOUTAD_"},
        {"BITRATE", "16"},
        {"SAMPLE_RATE", "32000"},
        {"GAIN", "5.0"},
        {"DURATION", "60"},
        {"IDRECORDER", "1"},
        {"SLEEPDURATION", "10"},
        {"GPIO_PIN", "117"}
    };

    // Sobreescribe con lo que haya en config.txt
    std::ifstream file(System::dataFilesFolder + "/config.txt");
    if (file.is_open()) {
        std::string line;
        while (std::getline(file, line)) {
            size_t sep = line.find('=');
            if (sep == std::string::npos) continue;
            std::string key = line.substr(0, sep);
            std::string val = line.substr(sep + 1);
            if (defaults.count(key)) defaults[key] = val;
        }
    }

    std::string json = "{";
    bool first = true;
    for (auto& kv : defaults) {
        if (!first) json += ",";
        json += "\"" + kv.first + "\":\"" + escapeJson(kv.second) + "\"";
        first = false;
    }
    json += "}";
    return json;
}

string SaveConfig::exec(string params)
{
    const std::vector<std::string> keys = {
        "STATION", "BITRATE", "SAMPLE_RATE", "GAIN",
        "DURATION", "IDRECORDER", "SLEEPDURATION", "GPIO_PIN"
    };

    std::ofstream file(System::dataFilesFolder + "/config.txt", std::ios::trunc);
    if (!file.is_open())
        return "{\"ok\":false,\"error\":\"cannot write config\"}";

    for (auto& key : keys) {
        std::string val = getPostParam(params, key);
        if (!val.empty())
            file << key << "=" << val << "\n";
    }
    file.close();

    // Reinicia el contenedor recorder en background
    std::thread([]() {
        std::this_thread::sleep_for(std::chrono::milliseconds(300));
        system("docker restart bird-recorder");
    }).detach();

    return "{\"ok\":true}";
}

string MemoryStatus::exec(string params)
{
    std::error_code ec;
    auto info = std::filesystem::space(System::dataFilesFolder, ec);
    if (ec) {
        return "{\"ok\":false,\"error\":\"cannot read disk usage\"}";
    }

    uintmax_t used = info.capacity - info.available;
    double usedPercent = info.capacity == 0 ? 0.0 : (double)used * 100.0 / (double)info.capacity;

    AutoCleanupResult cleanup = runAutoCleanupIfNeeded(usedPercent);
    if (cleanup.ran) {
        info = std::filesystem::space(System::dataFilesFolder, ec);
        if (!ec) {
            used = info.capacity - info.available;
            usedPercent = info.capacity == 0 ? 0.0 : (double)used * 100.0 / (double)info.capacity;
        }
    }

    uintmax_t wavCount = 0;
    uintmax_t pngCount = 0;
    uintmax_t wavBytes = 0;
    uintmax_t pngBytes = 0;

    std::filesystem::path recordings = std::filesystem::path(System::dataFilesFolder) / "recordings";
    if (std::filesystem::exists(recordings, ec)) {
        for (const auto& entry : std::filesystem::recursive_directory_iterator(recordings, std::filesystem::directory_options::skip_permission_denied, ec)) {
            if (ec) break;
            if (!entry.is_regular_file(ec)) continue;

            uintmax_t size = entry.file_size(ec);
            if (ec) size = 0;

            if (hasExtension(entry.path(), ".wav")) {
                wavCount++;
                wavBytes += size;
            } else if (hasExtension(entry.path(), ".png")) {
                pngCount++;
                pngBytes += size;
            }
        }
    }

    std::ostringstream json;
    json << std::fixed << std::setprecision(2);
    json << "{";
    json << "\"ok\":true,";
    json << "\"capacity\":" << info.capacity << ",";
    json << "\"available\":" << info.available << ",";
    json << "\"used\":" << used << ",";
    json << "\"used_percent\":" << usedPercent << ",";
    json << "\"wav_count\":" << wavCount << ",";
    json << "\"wav_bytes\":" << wavBytes << ",";
    json << "\"spectrogram_count\":" << pngCount << ",";
    json << "\"spectrogram_bytes\":" << pngBytes << ",";
    json << "\"auto_cleanup_enabled\":" << (autoCleanupEnabled() ? "true" : "false") << ",";
    json << "\"auto_cleanup_ran\":" << (cleanup.ran ? "true" : "false") << ",";
    json << "\"auto_cleanup_wav_removed\":" << cleanup.wavRemoved << ",";
    json << "\"auto_cleanup_png_removed\":" << cleanup.pngRemoved << ",";
    json << "\"auto_cleanup_csv_rows_removed\":" << cleanup.csvRowsRemoved;
    json << "}";
    return json.str();
}

string ClearStats::exec(string params)
{
    try {
        std::filesystem::path sensorCsv = std::filesystem::path(System::dataFilesFolder) / "sensor_history.csv";
        std::filesystem::path cpuTemp = std::filesystem::path(System::dataFilesFolder) / "cpu_temp.txt";

        writeSensorCsvHeader(sensorCsv);
        std::ofstream(cpuTemp, std::ios::trunc).close();
        return "{\"ok\":true}";
    } catch (...) {
        return "{\"ok\":false,\"error\":\"cannot clear stats files\"}";
    }
}

string ClearSpectrograms::exec(string params)
{
    try {
        std::filesystem::path recordings = std::filesystem::path(System::dataFilesFolder) / "recordings";
        uintmax_t removed = removeFilesWithExtension(recordings, ".png");
        return "{\"ok\":true,\"removed\":" + std::to_string(removed) + "}";
    } catch (...) {
        return "{\"ok\":false,\"error\":\"cannot clear spectrograms\"}";
    }
}

string ClearAudios::exec(string params)
{
    try {
        std::filesystem::path recordings = std::filesystem::path(System::dataFilesFolder) / "recordings";
        uintmax_t removed = removeFilesWithExtension(recordings, ".wav");
        return "{\"ok\":true,\"removed\":" + std::to_string(removed) + "}";
    } catch (...) {
        return "{\"ok\":false,\"error\":\"cannot clear audios\"}";
    }
}

string GetAutoCleanup::exec(string params)
{
    return std::string("{\"ok\":true,\"enabled\":") + (autoCleanupEnabled() ? "true" : "false") + "}";
}

string SaveAutoCleanup::exec(string params)
{
    std::string enabled = getPostParam(params, "enabled");
    bool isEnabled = enabled == "1" || enabled == "true" || enabled == "on";

    if (!writeAutoCleanupEnabled(isEnabled)) {
        return "{\"ok\":false,\"error\":\"cannot write auto cleanup config\"}";
    }

    return std::string("{\"ok\":true,\"enabled\":") + (isEnabled ? "true" : "false") + "}";
}
