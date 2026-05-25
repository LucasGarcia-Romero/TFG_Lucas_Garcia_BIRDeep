#pragma once
#include <string>

std::string buildSensorHistoryJson(const std::string& queryString, const std::string& dataDir);
std::string buildLatestSensorJson(const std::string& dataDir);

// Compatibilidad con la ruta antigua /temperature/history
std::string buildTemperatureHistoryJson(const std::string& queryString, const std::string& dataDir);
