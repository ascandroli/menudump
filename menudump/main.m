//
//  main.m
//  menudump
//
//  Created by Charles Wise on 2/17/13.
//

#include "UIAccess.h"
#include "Logger.h"

NSRunningApplication *getAppByPid(pid_t pid) {
    debug(@"Searching through NSWorkspace for pid %i", pid);
    NSArray *appNames = [[NSWorkspace sharedWorkspace] runningApplications];
    for (NSRunningApplication *app in appNames) {
        if (app.processIdentifier == pid) {
            debug(@"Found NSRunningApplication for pid %i", pid);
            return app;
        }
    }
    return nil;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        pid_t pid = -1;
        bool showHelp = false;

        bool outputYaml = false;
        bool outputAlfred = false;

        int debugLevel = 0;
        int offset = 1;
        while (offset < argc) {
            char const *value = argv[offset];
            if (strncasecmp(value, "--help", 6) == 0) {
                showHelp = true;
                offset++;
            } else if (strncasecmp(value, "--yaml", 6) == 0) {
                outputYaml = true;
                offset++;
            } else if (strncasecmp(value, "--alfred", 6) == 0) {
                outputAlfred = true;
                offset++;
            } else if (strncasecmp(value, "--pid", 5) == 0) {
                if (argc >= (offset + 1)) {
                    pid = atoi(argv[offset + 1]);
                    offset = offset + 2;
                }
            } else if (strncasecmp(value, "--debug", 7) == 0) {
                debugLevel++;
                offset++;
            } else {
                offset++;
            }
        }

        if (debugLevel >=2) {
            [Logger singleton].logThreshold = kTrace;
        } else if (debugLevel == 1) {
            [Logger singleton].logThreshold = kDebug;
        }

        if (showHelp) {
            printf("menudump v1.2\n");
            printf("Usage: menudump [--pid <pid>] [--yaml] [--alfred] [--help]\n");
            printf("  Dumps the menu contents of a given application in JSON format. Defaults to the front-most application.\n");
            printf("  --pid <pid> to target a specific application.\n");
            printf("  --yaml to output in YAML format instead.\n");
            printf("  --alfred to output in Alfred's Script Filter JSON Format.\n");
            printf("  --debug to turn on debug output.\n");
            printf("  --help print this message\n");
            exit(1);
        }

        NSRunningApplication *menuApp = nil;
        if (pid == -1) {
            menuApp = [[NSWorkspace sharedWorkspace] menuBarOwningApplication];
            if (!menuApp) {
                printf("Unable to find the app that owns the menu bar");
                exit(1);
            }
        } else {
            menuApp = getAppByPid(pid);
        }

        if (menuApp) {
            UIAccess *ui = [[UIAccess new] autorelease];
            NSArray *menu = [ui getAppMenu:menuApp];
            if (menu && [menu count] == 0) {
                printf("The menu structure wasn't readable. Make sure that 'Enable access for assistive devices' is checked in OS/X Settings.");
                exit(1);
            }
            NSString *contents;

            if (outputYaml) {
                contents = [ui convertMenuToYAML:menu app:menuApp];
            } else  if (outputAlfred) {
                contents = [ui convertMenuToAlfredScriptFilterFormat:menu app:menuApp];
            } else {
                contents = [ui convertMenuToJSON:menu app:menuApp];
            }

            printf("%s", [contents UTF8String]);
        } else {
            printf("Unable to find the app that matches the pid");
            exit(1);
        }
    }

    return 0;
}

