#pragma once
#include "common.h"

class PostMethod
{
public:
    string name;
    PostMethod() {};
    PostMethod(std::string name):name(name) {};
    virtual string exec(string params)=0;
    static string getPostParam(string paramList, string paramName) {
        std::string search = paramName + "=";
        size_t paramIdx = paramList.find(search);
        while (paramIdx != std::string::npos) {
            if (paramIdx == 0 || paramList[paramIdx - 1] == '&') break;
            paramIdx = paramList.find(search, paramIdx + 1);
        }
        if (paramIdx == std::string::npos) return "";
        size_t valueStart = paramIdx + search.size();
        size_t valueEnd   = paramList.find('&', valueStart);
        if (valueEnd == std::string::npos) valueEnd = paramList.size();
        return paramList.substr(valueStart, valueEnd - valueStart);
    }
};

class Login : public PostMethod { public: Login() :PostMethod("/login") { }; virtual string exec(string params) override; };
class ListWavFiles : public PostMethod { public: virtual string exec(string params) override; };
class ListFiles : public PostMethod { public: ListFiles() :PostMethod("/listFiles") { }; virtual string exec(string params) override; };
class RecordData : public PostMethod { public: RecordData() :PostMethod("/recordData") { }; virtual string exec(string params) override; };
class GetConfig : public PostMethod { public: GetConfig() :PostMethod("/getConfig") { }; virtual string exec(string params) override; };
class SaveConfig : public PostMethod { public: SaveConfig() :PostMethod("/saveConfig") { }; virtual string exec(string params) override; };
