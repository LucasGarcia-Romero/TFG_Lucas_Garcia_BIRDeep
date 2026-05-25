#pragma once
#define _CRT_SECURE_NO_WARNINGS
#include <sys/types.h>
#ifdef __linux__
#include <sys/socket.h>
#include <arpa/inet.h>
#include <netinet/in.h>
#include <unistd.h>
#endif
#ifdef _MSC_VER
#include <winsock2.h>
#include <Ws2tcpip.h>
#define MSG_NOSIGNAL 0
#endif
#include <string.h>
#include <list>
#include <map>
#include <vector>
#include <thread>
#include <mutex>
#include <string>
#include <chrono>
#include <iostream>
#include <fstream>
#include <cctype>
#include <iomanip>
#include <sstream>
#include <regex>
#include <filesystem>
#define DEBUG
#ifdef DEBUG
#define DEBUG_MSG(...)  printf(__VA_ARGS__);
#endif
using namespace std;
using namespace std::chrono_literals;

template<typename t>
std::ostream& operator<<(std::ostream& os, std::vector<t> v)
{
    for (auto& c : v) os << c;
    return os;
}

inline std::string decodeURIComponent(std::string encoded) {
    std::string decoded = encoded;
    std::smatch sm;
    std::string haystack;
    size_t dynamicLength = decoded.size() - 2;
    if (decoded.size() < 3) return decoded;
    for (size_t i = 0; i < dynamicLength; i++) {
        haystack = decoded.substr(i, 3);
        if (std::regex_match(haystack, sm, std::regex("%[0-9A-F]{2}"))) {
            haystack = haystack.replace(0, 1, "0x");
            std::string rc = { (char)std::stoi(haystack, nullptr, 16) };
            decoded = decoded.replace(decoded.begin() + i, decoded.begin() + i + 3, rc);
        }
        dynamicLength = decoded.size() - 2;
    }
    return decoded;
}

inline std::string encodeURIComponent(std::string decoded)
{
    std::ostringstream oss;
    std::regex r("[!'\\(\\)*-.0-9A-Za-z_~]");
    for (char& c : decoded) {
        std::string sc;
        sc += c;
        if (std::regex_match(sc, r)) oss << c;
        else oss << "%" << std::uppercase << std::hex << (0xff & c);
    }
    return oss.str();
}

inline std::string readFile(std::string fileName)
{
    std::string s="";
    std::ifstream fs;
    fs.open(fileName, std::ios_base::binary | std::ios::ate);
    if (fs) {
        long sz = (long)fs.tellg();
        fs.seekg(0);
        s.resize(sz);
        fs.read((char*)s.data(), sz);
        fs.close();
    }
    return s;
}

inline void replaceSubstrs(string& in, string pattern,string replaceStr) {
    string::size_type n = pattern.length();
    for (string::size_type i = in.find(pattern); i != string::npos; i = in.find(pattern)) {
        in.erase(i, n);
        in.insert(i, replaceStr);
    }
}
