#pragma once
#include "common.h"
class System
{
public:
    static inline string htmlFilesFolder = "html";
    static inline string dataFilesFolder = "data";
    static inline int serverPort = 80;
    static inline void parseParams(int argc, char** argv)
    {
        for (int i = 1; i < argc; i++)
        {
            if (string(argv[i]) == "--serverPort") { i++; serverPort = atoi(argv[i]); }
            if (string(argv[i]) == "--htmlFilesFolder") { i++; htmlFilesFolder = argv[i]; }
            if (string(argv[i]) == "--dataFilesFolder") { i++; dataFilesFolder = argv[i]; }
        }
    }
};
