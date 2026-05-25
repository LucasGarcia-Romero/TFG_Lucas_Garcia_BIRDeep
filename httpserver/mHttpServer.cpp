// Es el punto de inicio del programa

#include <iostream>
#include "lib/HttpServer.h"
#include "lib/System.h"
#include "lib/PostMethod.h"

int main(int argc, char** argv)
{
    // lee argumentos de arranque
    System::parseParams(argc, argv);

    // levanta un servidor Http + abrir socket
    HttpServer* s = new HttpServer(System::serverPort);

    // Endpoints POST
    s->registerPostMethod(new Login());
    s->registerPostMethod(new ListFiles());
    s->registerPostMethod(new RecordData());
    s->registerPostMethod(new GetConfig());
    s->registerPostMethod(new SaveConfig());

    // Endpoints de memoria / limpieza
    s->registerPostMethod(new MemoryStatus());
    s->registerPostMethod(new ClearStats());
    s->registerPostMethod(new ClearSpectrograms());
    s->registerPostMethod(new ClearAudios());

    // Entra en el bucle infinito
    s->mainLoop();
    delete s;
}
