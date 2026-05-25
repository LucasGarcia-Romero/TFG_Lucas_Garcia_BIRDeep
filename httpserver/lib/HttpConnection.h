#pragma once
#include "common.h"
#include "PostMethod.h"
#include <map>
#include <string>

typedef struct { int size; unsigned char* data; } msg_t;
typedef struct { unsigned int id; unsigned int serverId; int socket; bool alive; } connection_t;
typedef struct { bool sendBody; std::string header; std::string type; std::string body; } httpResponse_t;

class HttpConnection {
private:
    int id;
    connection_t conn;
    httpResponse_t response;
    std::string rawHttpPacket;
    std::map<std::string, std::string> parameters;
    std::map<std::string, std::string> mimeTypes;
    std::map<std::string, PostMethod*> postMethods;
    std::string runCommand(const std::string& cmd);
    std::string trim(const std::string& s);
    std::string escapeJson(const std::string& s);
    std::string extractWavName(const std::string& text);
    std::string buildStatusJson();
    std::string buildTemperatureJson();
public:
    HttpConnection(int id, connection_t conn, std::map<std::string, PostMethod*> methods)
        :id(id), conn(conn), postMethods(methods) { buildMimeTypes(); }
    void parseLine(std::string& line);
    void parseMethod(std::string& line);
    void recvHttpPacket();
    void parseHttpPacket();
    void sendHttpPacket();
    void clientLoop();
    std::string readLine();
    std::string readData(size_t length);
    void buildMimeTypes();
    string createHeader(std::string responseCode, string contentType, size_t contentLength);
    string readFileFromFolder(string fileName);
};
