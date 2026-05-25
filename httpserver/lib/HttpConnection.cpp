// Expone las rutas publicas

#include "HttpConnection.h"
#include "temperature_history.h"
#include "System.h"

#include <array>
#include <cstdio>
#include <regex>
#include <sstream>

std::string HttpConnection::readData(size_t length)
{
    size_t recvSize = 0;
    std::string line;
    line.resize(length);
    recvSize = recv(conn.socket, (char*)line.data(), (int)length, 0);
    if (recvSize != length) conn.alive = false;
    return line;
}

std::string HttpConnection::readLine()
{
    char buf[1];
    int recvSize = 0;
    std::string line;
    do {
        recvSize = recv(conn.socket, &buf[0], 1, 0);
        if (recvSize == 1) line.push_back(buf[0]);
        else conn.alive = false;
    } while (buf[0] != '\n' && recvSize == 1);
    line.push_back('\0');
    return line;
}

void HttpConnection::buildMimeTypes()
{
    this->mimeTypes["aac"] = "audio/aac";
    this->mimeTypes["abw"] = "application/x-abiword";
    this->mimeTypes["arc"] = "application/octet-stream";
    this->mimeTypes["avi"] = "video/x-msvideo";
    this->mimeTypes["azw"] = "application/vnd.amazon.ebook";
    this->mimeTypes["bin"] = "application/octet-stream";
    this->mimeTypes["bz"] = "application/x-bzip";
    this->mimeTypes["bz2"] = "application/x-bzip2";
    this->mimeTypes["csh"] = "application/x-csh";
    this->mimeTypes["css"] = "text/css";
    this->mimeTypes["csv"] = "text/csv";
    this->mimeTypes["doc"] = "application/msword";
    this->mimeTypes["epub"] = "application/epub+zip";
    this->mimeTypes["gif"] = "image/gif";
    this->mimeTypes["htm"] = "text/html";
    this->mimeTypes["html"] = "text/html";
    this->mimeTypes["ico"] = "image/x-icon";
    this->mimeTypes["ics"] = "text/calendar";
    this->mimeTypes["jar"] = "application/java-archive";
    this->mimeTypes["jpeg"] = "image/jpeg";
    this->mimeTypes["jpg"] = "image/jpeg";
    this->mimeTypes["js"] = "application/javascript";
    this->mimeTypes["json"] = "application/json";
    this->mimeTypes["mid"] = "audio/midi";
    this->mimeTypes["midi"] = "audio/midi";
    this->mimeTypes["mpeg"] = "video/mpeg";
    this->mimeTypes["mpkg"] = "application/vnd.apple.installer+xml";
    this->mimeTypes["odp"] = "application/vnd.oasis.opendocument.presentation";
    this->mimeTypes["ods"] = "application/vnd.oasis.opendocument.spreadsheet";
    this->mimeTypes["odt"] = "application/vnd.oasis.opendocument.text";
    this->mimeTypes["oga"] = "audio/ogg";
    this->mimeTypes["ogv"] = "video/ogg";
    this->mimeTypes["ogx"] = "application/ogg";
    this->mimeTypes["pdf"] = "application/pdf";
    this->mimeTypes["png"] = "image/png";
    this->mimeTypes["ppt"] = "application/vnd.ms-powerpoint";
    this->mimeTypes["rar"] = "application/x-rar-compressed";
    this->mimeTypes["rtf"] = "application/rtf";
    this->mimeTypes["sh"] = "application/x-sh";
    this->mimeTypes["svg"] = "image/svg+xml";
    this->mimeTypes["swf"] = "application/x-shockwave-flash";
    this->mimeTypes["tar"] = "application/x-tar";
    this->mimeTypes["tif"] = "image/tiff";
    this->mimeTypes["tiff"] = "image/tiff";
    this->mimeTypes["ttf"] = "font/ttf";
    this->mimeTypes["vsd"] = "application/vnd.visio";
    this->mimeTypes["wav"] = "audio/x-wav";
    this->mimeTypes["weba"] = "audio/webm";
    this->mimeTypes["webm"] = "video/webm";
    this->mimeTypes["webp"] = "image/webp";
    this->mimeTypes["woff"] = "font/woff";
    this->mimeTypes["woff2"] = "font/woff2";
    this->mimeTypes["xhtml"] = "application/xhtml+xml";
    this->mimeTypes["xls"] = "application/vnd.ms-excel";
    this->mimeTypes["xml"] = "application/xml";
    this->mimeTypes["xul"] = "application/vnd.mozilla.xul+xml";
    this->mimeTypes["zip"] = "application/zip";
    this->mimeTypes["3gp"] = "video/3gpp";
    this->mimeTypes["3g2"] = "video/3gpp2";
    this->mimeTypes["7z"] = "application/x-7z-compressed";
}

void HttpConnection::parseMethod(std::string& line)
{
    int methodEnd = line.find(' ');
    std::string method = line.substr(0, methodEnd);
    size_t urlEnd = line.find(' ', methodEnd + 1);
    if (urlEnd == std::string::npos) urlEnd = line.find('\r');
    std::string url = line.substr(methodEnd + 1, urlEnd - (methodEnd + 1));
    parameters["METHOD"] = method;
    parameters["METHODURL"] = url;
}

void HttpConnection::parseLine(std::string& line)
{
    size_t keyEnd = line.find(':');
    std::string key = line.substr(0, keyEnd);
    size_t valueEnd = line.find('\r');
    std::string value = line.substr(keyEnd + 1, valueEnd - (keyEnd + 1));
    parameters[key] = value;
}

void HttpConnection::recvHttpPacket()
{
    parameters.clear();
    rawHttpPacket = "";
    std::string line;
    line = readLine();
    rawHttpPacket += line;
    parseMethod(line);
    do {
        line = readLine();
        parseLine(line);
        rawHttpPacket += line;
    } while (!line.empty() && line[0] != '\0' > 0 && line[0] != '\r');

    auto method = parameters.find("METHOD");
    if (method != parameters.end() && method->second == "POST") {
        int contentLength = std::stoi(parameters.find("Content-Length")->second);
        line = decodeURIComponent(readData(contentLength));
        parameters["METHODPARAMS"] = line;
        rawHttpPacket += line;
    }
}

string HttpConnection::readFileFromFolder(string fileName)
{
    string f = readFile(System::htmlFilesFolder + fileName);
    if (f.length() == 0) f = readFile(System::dataFilesFolder + fileName);
    return f;
}

std::string HttpConnection::trim(const std::string& s)
{
    size_t start = s.find_first_not_of(" \t\r\n");
    if (start == std::string::npos) return "";
    size_t end = s.find_last_not_of(" \t\r\n");
    return s.substr(start, end - start + 1);
}

std::string HttpConnection::escapeJson(const std::string& s)
{
    std::string out;
    for (char c : s) {
        switch (c) {
        case '\"': out += "\\\""; break;
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

std::string HttpConnection::runCommand(const std::string& cmd)
{
    std::array<char, 256> buffer;
    std::string result;
    FILE* pipe = popen(cmd.c_str(), "r");
    if (!pipe) return "";
    while (fgets(buffer.data(), (int)buffer.size(), pipe) != nullptr) result += buffer.data();
    pclose(pipe);
    return result;
}

std::string HttpConnection::extractWavName(const std::string& text)
{
    std::regex rgx(R"(/data/recordings/([^\s]+\.wav))");
    std::smatch match;
    if (std::regex_search(text, match, rgx)) return match[1];
    return "";
}

std::string HttpConnection::buildStatusJson()
{
    std::string containerStatus = trim(runCommand("docker inspect -f '{{.State.Status}}' bird-recorder 2>/dev/null"));
    std::string topOutput = runCommand("docker top bird-recorder 2>/dev/null");
    std::string recordLine = "";
    std::string soxLine = "";
    std::istringstream iss(topOutput);
    std::string line;
    while (std::getline(iss, line)) {
        if (line.find("record.sh") != std::string::npos) recordLine = trim(line);
        if (line.find("sox") != std::string::npos) soxLine = trim(line);
    }

    bool containerRunning = (containerStatus == "running");
    bool recordRunning = !recordLine.empty();
    bool soxRunning = !soxLine.empty();
    std::string currentFile = extractWavName(soxLine);
    std::string json = "{";
    json += "\"container_status\":\"" + escapeJson(containerStatus) + "\",";
    json += "\"container_running\":" + std::string(containerRunning ? "true" : "false") + ",";
    json += "\"record_running\":" + std::string(recordRunning ? "true" : "false") + ",";
    json += "\"record_command\":\"" + escapeJson(recordLine) + "\",";
    json += "\"sox_running\":" + std::string(soxRunning ? "true" : "false") + ",";
    json += "\"sox_command\":\"" + escapeJson(soxLine) + "\",";
    json += "\"current_file\":\"" + escapeJson(currentFile) + "\"";
    json += "}";
    return json;
}

std::string HttpConnection::buildTemperatureJson()
{
    std::string tempStr = trim(runCommand("cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null"));
    int tempValue = 0;
    if (!tempStr.empty()) tempValue = std::stoi(tempStr) / 1000;
    return "{\"cpu_temp\":" + std::to_string(tempValue) + "}";
}

void HttpConnection::parseHttpPacket()
{
    std::cout << rawHttpPacket << "\n";
    auto methodNode = parameters.end();
    response.header = response.body = response.type = "";

    if ((methodNode = parameters.find("METHOD")) != parameters.end()) {
        auto method = methodNode->second;
        if (method == "GET") {
            auto fullUrl = parameters.find("METHODURL")->second;
            std::string url;
            std::string queryString;
            size_t qPos = fullUrl.find('?');
            if (qPos != std::string::npos) {
                url = fullUrl.substr(0, qPos);
                queryString = fullUrl.substr(qPos + 1);
            } else {
                url = fullUrl;
                queryString = "";
            }
            if (url.ends_with('/')) url = "/";

            if (url == "/status") {
                response.type = mimeTypes["json"];
                response.body = buildStatusJson();
                response.header = createHeader("200 OK", response.type, response.body.length());
                response.sendBody = true;
                return;
            }

            if (url == "/sensors/latest" || url == "/temperature") {
                response.type = mimeTypes["json"];
                response.body = buildLatestSensorJson(System::dataFilesFolder);
                response.header = createHeader("200 OK", response.type, response.body.length());
                response.sendBody = true;
                return;
            }

            if (url == "/sensors/history" || url == "/temperature/history") {
                response.type = mimeTypes["json"];
                response.body = buildSensorHistoryJson(queryString, System::dataFilesFolder);
                response.header = createHeader("200 OK", response.type, response.body.length());
                response.sendBody = true;
                return;
            }

            if (url == "/config") {
                response.type = mimeTypes["json"];
                response.body = postMethods["/getConfig"]->exec("");
                response.header = createHeader("200 OK", response.type, response.body.length());
                response.sendBody = true;
                return;
            }

            if (url == "/") {
                response.type = mimeTypes["html"];
                response.body = readFileFromFolder("/index.html");
            } else {
                response.body = readFileFromFolder(url);
                size_t extensionPos = url.rfind('.');
                if (extensionPos != std::string::npos) {
                    auto mimeExtension = url.substr(extensionPos + 1);
                    if (mimeTypes.find(mimeExtension) != mimeTypes.end()) response.type = mimeTypes[mimeExtension];
                    else response.type = "application/octet-stream";
                } else {
                    response.type = "application/octet-stream";
                }
            }

            if (response.body.empty()) {
                response.header = createHeader("404 Not Found", response.type, response.body.length());
                response.sendBody = false;
            } else {
                response.header = createHeader("200 OK", response.type, response.body.length());
                response.sendBody = true;
            }
        } else if (method == "POST") {
            auto url = parameters.find("METHODURL")->second;
            PostMethod* method = postMethods[url];
            if (method != nullptr) {
                response.sendBody = true;
                response.type = mimeTypes["html"];
                response.body = method->exec(parameters["METHODPARAMS"]);
                response.header = createHeader("200 OK", response.type, response.body.length());
            } else {
                response.sendBody = false;
                response.type = mimeTypes["html"];
                response.body = "";
                response.header = createHeader("404 Not Found", response.type, response.body.length());
            }
        }
    }
}

std::string HttpConnection::createHeader(std::string responseCode, std::string contentType, size_t contentLength)
{
    std::string httpHeader = "";
    if (responseCode == "404 Not Found") {
        httpHeader += "HTTP/1.1 404 Not Found\r\n";
        httpHeader += "Connection: keep-alive\r\n";
        httpHeader += "Content-length: " + std::to_string(0) + "\r\n";
    } else {
        httpHeader += "HTTP/1.1 " + responseCode + "\r\n";
        httpHeader += "Connection: keep-alive\r\n";
        httpHeader += "Keep-Alive: timeout = 5, max = 1000\r\n";
        httpHeader += "Content-type: " + contentType + "\r\n";
        httpHeader += "Content-length: " + std::to_string(contentLength) + "\r\n";
        httpHeader += "Accept-Ranges: bytes\r\n";
        httpHeader += "Access-Control-Allow-Origin: *\r\n";
    }
    httpHeader += "\r\n";
    return httpHeader;
}

void HttpConnection::sendHttpPacket()
{
    std::string httpPacket = response.header;
    if (response.sendBody) httpPacket += response.body;
    send(conn.socket, httpPacket.c_str(), (int)httpPacket.length(), MSG_NOSIGNAL);
}

void HttpConnection::clientLoop()
{
    while (conn.alive) {
        recvHttpPacket();
        parseHttpPacket();
        sendHttpPacket();
    }
    std::cout << "closed client\n";
}
