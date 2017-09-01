//
//  UIAccess.m
//  menudump
//
//  Created by Charles Wise on 3/3/13.
//

#import "UIAccess.h"
#import "MenuItem.h"
#import "Logger.h"

@implementation UIAccess

id getAttribute(AXUIElementRef element, CFStringRef attribute) {
    trace(@"Getting attribute %@", attribute);
    CFTypeRef value = nil;
    if (AXUIElementCopyAttributeValue(element, attribute, &value) != kAXErrorSuccess) return nil;
    if (AXValueGetType((AXValueRef) value) == kAXValueAXErrorType) return nil;
    return value;
}

bool __unused isEnabled(AXUIElementRef element) {
    CFTypeRef enabled = NULL;
    if (AXUIElementCopyAttributeValue(element, kAXEnabledAttribute, &enabled) != kAXErrorSuccess) return false;
    return CFBooleanGetValue(enabled);
}

long getLongAttribute(AXUIElementRef element, CFStringRef attribute) {
    CFNumberRef valueRef = (CFNumberRef) getAttribute(element, attribute);
    long result = 0;
    if (valueRef) {
        CFNumberGetValue(valueRef, kCFNumberLongType, &result);
    }
    return result;
}

NSString *decodeKeyMask(long cmdModifiers) {
    trace(@"Decoding key mask %li", cmdModifiers)
    NSString *result = @"";
    if (cmdModifiers == 0x18) {
        result = @"fn fn";
    } else {
        if (cmdModifiers & 0x04) {
            result = [result stringByAppendingString:@"⌃"];
        }
        if (cmdModifiers & 0x02) {
            result = [result stringByAppendingString:@"⌥"];
        }
        if (cmdModifiers & 0x01) {
            result = [result stringByAppendingString:@"⇧"];
        }
        if (!(cmdModifiers & 0x08)) {
            result = [result stringByAppendingString:@"⌘"];
        }
    }
    return result;
}

NSString *getMenuItemShortcut(AXUIElementRef element, NSDictionary *virtualKeys) {
    trace(@"Getting menu item shortcut");
    NSString *result = nil;

    NSString *cmdChar = getAttribute(element, kAXMenuItemCmdCharAttribute);
    NSString *base = cmdChar;
    long cmdModifiers = getLongAttribute(element, kAXMenuItemCmdModifiersAttribute);
    long cmdVirtualKey = getLongAttribute(element, kAXMenuItemCmdVirtualKeyAttribute);

    if (base) {
        if ([base characterAtIndex:0] == 0x7f) {
            base = @"⌦";
        }
    } else if (cmdVirtualKey > 0) {
        NSString *virtualLookup = [virtualKeys objectForKey:[NSNumber numberWithLong:cmdVirtualKey]];
        if (virtualLookup) {
            base = virtualLookup;
        }
    }
    NSString *modifiers = decodeKeyMask(cmdModifiers);
    if (base) {
        result = [modifiers stringByAppendingString:base];
    }
    trace(@"Shortcut is %@", result);
    return result;
}

bool shouldSkip(NSString * bundleIdentifier, NSInteger depth, NSString * name) {
    bool result = false;

    // Skip the top-level Apple menu
    if (depth == 0 && [name isEqualToString:@"Apple"]) {
        result = true;
    } else if (depth == 2 && [name isEqualToString:@"Services"]) {
        result = true;
    } else if (depth == 0 && [bundleIdentifier isEqualToString:@"com.apple.Safari"]) {
        // These two menus are time-sucks in Safari
        if ([name isEqualToString:@"History"] || [name isEqualToString:@"Bookmarks"]) {
            result = true;
        }
    }

    trace(@"Check to see if we should skip menu item %@, at depth %i, for app %@", name, depth, bundleIdentifier);

    return result;
}

NSArray *menuItemsForElement(NSString *bundleIdentifier, AXUIElementRef element, NSInteger depth, NSInteger maxDepth, NSDictionary *virtualKeys) {
    debug(@"%@Looking at menu at depth %i", padding((int) depth), depth);
    NSArray *children = nil;
    AXUIElementCopyAttributeValue(element, kAXChildrenAttribute, (CFTypeRef *) &children);

    NSMutableArray *menuItems = [NSMutableArray array];
    for (id child in children) {
        // We don't have focus, so we can't skip disabled menu entries.
        // if (!isEnabled((AXUIElementRef) child)) continue;

        NSString *name = getAttribute((AXUIElementRef) child, kAXTitleAttribute);

        if (shouldSkip(bundleIdentifier, depth, name)) {
            continue;
        }

        // Get any children for this menu entry
        NSArray *mChildren = nil;
        AXUIElementCopyAttributeValue(element, kAXChildrenAttribute, (CFTypeRef *) &mChildren);
        NSUInteger mChildrenCount = [mChildren count];

        // Create the menu item tracking object
        MenuItem *menuItem = [[[MenuItem alloc] init] autorelease];
        menuItem.name = name;

        // Don't recurse further if a menu entry has too many children or we've hit max depth
        if (mChildrenCount > 0 || mChildrenCount < 40 || depth < maxDepth) {
            // Otherwise recurse on this menu item's children
            menuItem.children = menuItemsForElement(bundleIdentifier, (AXUIElementRef) child, depth + 1, maxDepth, virtualKeys);
        }

        // Save this menu item to the list if it has a name.
        if (name && [name length] > 0) {
            menuItem.shortcut = getMenuItemShortcut((AXUIElementRef) child, virtualKeys);

            [menuItems addObject:menuItem];
        } else {
            // This isn't a menu item, just save its children

            debug(@"%@Skipping menu item", padding((int)(depth + 1)));

            [menuItems addObjectsFromArray:menuItem.children];
        }
    }

    return menuItems;
}

NSString *escape(NSString *text) {
    NSString *result = [text stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"];
    result = [result stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
    return result;
}

NSString *padding(int length) {
    NSMutableString *padding = [NSMutableString stringWithString:@""];
    for (int i = 0; i < length; i++) {
        [padding appendString:@" "];
    }
    return padding;
}

NSString *buildLocator(MenuItem *item, NSArray *parents) {
    bool needLocator = parents && [parents count] > 0;
    NSArray *children = item.children;
    needLocator = needLocator && (!children || [children count] == 0);
    if (needLocator) {
        NSString *name = item.name;
        NSString *menuItem = [NSString stringWithFormat:@"menu item \"%@\"", name];
        NSMutableString *buffer = [NSMutableString stringWithString:menuItem];

        unsigned long pathCount = [parents count];
        for (NSString *parent in [parents reverseObjectEnumerator]) {
            NSString *menuType = @"menu bar item";
            if (pathCount > 1) {
                menuType = @"menu item";
            }
            NSString *menu = [NSString stringWithFormat:@" of menu \"%@\" of %@ \"%@\"", parent, menuType, parent];
            [buffer appendString:menu];
            pathCount--;
        }

        [buffer appendString:@" of menu bar 1"];

        return buffer;
    } else {
        return [NSMutableString stringWithString:@""];
    }
}

NSString *buildMenuPath(NSArray *parents) {
    if (!parents || [parents count] == 0) {
        return [NSMutableString stringWithString:@""];
    } else {
        NSMutableString *buffer = [NSMutableString stringWithString:@""];

        for (NSString *parent in parents) {
            if ([buffer length] > 0) {
                [buffer appendString:@" > "];
            }
            [buffer appendString:parent];
        }

        return buffer;
    }
}

NSArray *menuToJSON(NSArray *menu, int depth, NSArray *parents) {

    NSMutableArray *result = [NSMutableArray new];

    for (MenuItem *item in menu) {

        NSArray *children = [NSArray array];
        if (item.children && ([item.children count] > 0)) {
            NSArray *childParents = [NSArray arrayWithArray:parents];
            childParents = [childParents arrayByAddingObject:item.name];
            children = menuToJSON(item.children, depth + 2, childParents);
        }

        NSDictionary *menuItem = @{
                @"name": item.name ?: @"",
                @"shortcut": item.shortcut ?: @"",
                @"locator": buildLocator(item, parents),
                @"menuPath": buildMenuPath(parents),
                @"children": children
        };

        [result addObject:menuItem];
    }
    return result;
}

NSArray *menuToAlfredScriptFilterFormat(NSArray *menu, int depth, NSArray *parents, NSString *bundlePath) {

    NSMutableArray * result = [NSMutableArray new];

    for (MenuItem *item in menu) {

        NSArray *children = [NSArray array];
        if (item.children && ([item.children count] > 0)) {
            NSArray *childParents = [NSArray arrayWithArray:parents];
            childParents = [childParents arrayByAddingObject:item.name];
            children = menuToAlfredScriptFilterFormat(item.children, depth + 2, childParents, bundlePath);
        }

        NSString * locator = buildLocator(item, parents);

        if ([locator length] > 0) {
            NSDictionary *menuItem = @{
                    @"uid": [NSString stringWithFormat:@"%lu", [locator hash]],
                    @"title": [NSString stringWithFormat:@"%@%@", item.name ?: @"", item.shortcut ? [NSString stringWithFormat:@" \t (%@)", item.shortcut] : @""],
                    @"autocomplete": item.name ?: @"",
                    @"arg": buildLocator(item, parents),
                    @"subtitle": buildMenuPath(parents),
                    @"icon": @{
                            @"type": @"fileicon",
                            @"path": bundlePath
                    }
            };
            [result addObject:menuItem];
        }

        [result addObjectsFromArray:children];
    }

    return result;
}

NSString *menuToYAML(NSArray *menu, int startingOffset, NSArray *parents) {
    NSMutableString *buffer = [NSMutableString stringWithString:@""];
    NSString *offset = padding(startingOffset + 4);
    NSString *offset2 = padding(startingOffset + 6);
    for (MenuItem *item in menu) {
        [buffer appendString:offset];
        [buffer appendString:@"- "];
        NSString *shortcut = item.shortcut;
        if (!shortcut) {
            shortcut = @"";
        }
        [buffer appendString:[NSString stringWithFormat:@"name: \"%@\"\n", escape(item.name)]];
        [buffer appendString:offset2];
        [buffer appendString:[NSString stringWithFormat:@"shortcut: \"%@\"\n", escape(shortcut)]];

        NSString *children = @"";
        if (item.children && ([item.children count] > 0)) {
            NSArray *childParents = [NSArray arrayWithArray:parents];
            childParents = [childParents arrayByAddingObject:item.name];
            children = menuToYAML(item.children, startingOffset + 6, childParents);
        }

        [buffer appendString:offset2];
        [buffer appendString:[NSString stringWithFormat:@"locator: \"%@\"\n", escape(buildLocator(item, parents))]];
        [buffer appendString:offset2];
        [buffer appendString:[NSString stringWithFormat:@"menuPath: \"%@\"\n", escape(buildMenuPath(parents))]];
        if ([children length] > 0) {
            [buffer appendString:offset2];
            [buffer appendString:[NSString stringWithFormat:@"children:\n%@", children]];
        }
    }

    return buffer;
}

NSMutableDictionary * buildVirtualKeyDictionary() {
    NSMutableDictionary *virtualKeys = [NSMutableDictionary dictionary];

    virtualKeys[@0x24] = @"↩"; // kVK_Return
    virtualKeys[@0x30] = @"⇥"; // kVK_Tab
    virtualKeys[@0x31] = @"␣"; // kVK_Space
    virtualKeys[@0x33] = @"⌫"; // kVK_Delete
    virtualKeys[@0x35] = @"⎋"; // kVK_Escape
    virtualKeys[@0x39] = @"⇪"; // kVK_CapsLock
    virtualKeys[@0x3F] = @"fn"; // kVK_Function
    virtualKeys[@0x40] = @"F17"; // kVK_F17
    virtualKeys[@0x47] = @"⌧"; // kVK_ANSI_KeypadClear
    virtualKeys[@0x4C] = @"⌤"; // kVK_ANSI_KeypadEnter
    virtualKeys[@0x4F] = @"F18"; // kVK_F18
    virtualKeys[@0x50] = @"F19"; // kVK_F19
    virtualKeys[@0x5A] = @"F20"; // kVK_F20
    virtualKeys[@0x60] = @"F5"; // kVK_F5
    virtualKeys[@0x61] = @"F6"; // kVK_F6
    virtualKeys[@0x62] = @"F7"; // kVK_F7
    virtualKeys[@0x63] = @"F3"; // kVK_F3
    virtualKeys[@0x64] = @"F8"; // kVK_F8
    virtualKeys[@0x65] = @"F9"; // kVK_F9
    virtualKeys[@0x67] = @"F11"; // kVK_F11
    virtualKeys[@0x69] = @"F13"; // kVK_F13
    virtualKeys[@0x6A] = @"F16"; // kVK_F16
    virtualKeys[@0x6B] = @"F14"; // kVK_F14
    virtualKeys[@0x6D] = @"F10"; // kVK_F10
    virtualKeys[@0x6F] = @"F12"; // kVK_F12
    virtualKeys[@0x71] = @"F15"; // kVK_F15
    virtualKeys[@0x72] = @"INS"; // Insert
    virtualKeys[@0x73] = @"↖"; // kVK_Home
    virtualKeys[@0x74] = @"⇞"; // kVK_PageUp
    virtualKeys[@0x75] = @"⌦"; // kVK_ForwardDelete
    virtualKeys[@0x76] = @"F4"; // kVK_F4
    virtualKeys[@0x77] = @"↘"; // kVK_End
    virtualKeys[@0x78] = @"F2"; // kVK_F2
    virtualKeys[@0x79] = @"⇟"; // kVK_PageDown
    virtualKeys[@0x7A] = @"F1"; // kVK_F1
    virtualKeys[@0x7B] = @"←"; // kVK_LeftArrow
    virtualKeys[@0x7C] = @"→"; // kVK_RightArrow
    virtualKeys[@0x7D] = @"↓"; // kVK_DownArrow
    virtualKeys[@0x7E] = @"↑"; // kVK_UpArrow

    return virtualKeys;
}

- (NSArray *)getAppMenu:(NSRunningApplication *)menuApp {
    AXUIElementRef app = AXUIElementCreateApplication(menuApp.processIdentifier);
    AXUIElementRef menuBar;
    AXUIElementCopyAttributeValue(app, kAXMenuBarAttribute, (CFTypeRef *) &menuBar);

    return menuItemsForElement(menuApp.bundleIdentifier, menuBar, 0, 5, buildVirtualKeyDictionary());
}

- (NSString *)convertMenuToJSON:(NSArray *)menu app:(NSRunningApplication *)menuApp {
    debug(@"Converting menu to JSON");

    NSDictionary *dictionary = @{
            @"name": menuApp.localizedName,
            @"bundleIdentifier": menuApp.bundleIdentifier,
            @"bundlePath": menuApp.bundleURL.path,
            @"executablePath": menuApp.executableURL.path,
            @"menus": menuToJSON(menu, 2, [[[NSArray alloc] init] autorelease]),

    };

    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:dictionary options:0 error:nil];
    return [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
}

- (NSString *)convertMenuToAlfredScriptFilterFormat:(NSArray *)menu app:(NSRunningApplication *)menuApp {

    NSDictionary *dictionary = @{
            @"items": menuToAlfredScriptFilterFormat(menu, 2, [[[NSArray alloc] init] autorelease], menuApp.bundleURL.path),
    };

    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:dictionary options:0 error:nil];
    return [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
}

- (NSString *)convertMenuToYAML:(NSArray *)menu app:(NSRunningApplication *)menuApp {
    debug(@"Converting menu to YAML");
    NSMutableString *buffer = [NSMutableString stringWithString:@"application:\n"];
    [buffer appendString:@"    name: \""];
    [buffer appendString:menuApp.localizedName];
    [buffer appendString:@"\"\n"];
    [buffer appendString:@"    bundleIdentifier: \""];
    [buffer appendString:menuApp.bundleIdentifier];
    [buffer appendString:@"\"\n"];
    [buffer appendString:@"    bundlePath: \""];
    [buffer appendString:menuApp.bundleURL.path];
    [buffer appendString:@"\"\n"];
    [buffer appendString:@"    executablePath: \""];
    [buffer appendString:menuApp.executableURL.path];
    [buffer appendString:@"\"\n"];
    [buffer appendString:@"menus:\n"];
    [buffer appendString:menuToYAML(menu, 0, [[[NSArray alloc] init] autorelease])];
    return buffer;
}
@end
