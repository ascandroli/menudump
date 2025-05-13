#!/usr/bin/env swift

import Foundation
import Cocoa
import ApplicationServices

struct MenuItem {
    let path: [String]
    let pathIndices: String
    let shortcut: String
    let applescriptPath: String
    
    var title: String { path.last ?? "" }
    var subtitle: String { 
        var p = path
        p.removeLast()
        return p.joined(separator: " > ")
    }
}

struct AlfredItem {
    let uid: String
    let title: String
    let autocomplete: String
    let arg: String
    let subtitle: String
    let match: String
    let icon: [String: String]
    
    var dictionary: [String: Any] {
        return [
            "uid": uid,
            "title": title,
            "autocomplete": autocomplete,
            "arg": arg,
            "subtitle": subtitle,
            "match": match,
            "icon": icon
        ]
    }
}

// MARK: - Virtual Key Mappings
let virtualKeys = [
    0x24: "↩", // kVK_Return
    0x4c: "⌤", // kVK_ANSI_KeypadEnter
    0x47: "⌧", // kVK_ANSI_KeypadClear
    0x30: "⇥", // kVK_Tab
    0x31: "␣", // kVK_Space
    0x33: "⌫", // kVK_Delete
    0x35: "⎋", // kVK_Escape
    0x39: "⇪", // kVK_CapsLock
    0x3f: "fn", // kVK_Function
    0x7a: "F1", // kVK_F1
    0x78: "F2", // kVK_F2
    0x63: "F3", // kVK_F3
    0x76: "F4", // kVK_F4
    0x60: "F5", // kVK_F5
    0x61: "F6", // kVK_F6
    0x62: "F7", // kVK_F7
    0x64: "F8", // kVK_F8
    0x65: "F9", // kVK_F9
    0x6d: "F10", // kVK_F10
    0x67: "F11", // kVK_F11
    0x6f: "F12", // kVK_F12
    0x69: "F13", // kVK_F13
    0x6b: "F14", // kVK_F14
    0x71: "F15", // kVK_F15
    0x6a: "F16", // kVK_F16
    0x40: "F17", // kVK_F17
    0x4f: "F18", // kVK_F18
    0x50: "F19", // kVK_F19
    0x5a: "F20", // kVK_F20
    0x73: "↖", // kVK_Home
    0x74: "⇞", // kVK_PageUp
    0x75: "⌦", // kVK_ForwardDelete
    0x77: "↘", // kVK_End
    0x79: "⇟", // kVK_PageDown
    0x7b: "◀︎", // kVK_LeftArrow
    0x7c: "▶︎", // kVK_RightArrow
    0x7d: "▼", // kVK_DownArrow
    0x7e: "▲", // kVK_UpArrow
]


// DJB2 hash function for consistent UIDs across runs
extension String {
    var djb2Hash: Int {
        return self.utf8.reduce(5381) { ($0 << 5) &+ $0 &+ Int($1) }
    }
}

// MARK: - Helper Functions

func getAttribute(element: AXUIElement, name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    AXUIElementCopyAttributeValue(element, name as CFString, &value)
    return value
}

let halfWidthSpace = " " // THIN SPACE (U+2009)

func decodeModifiers(_ modifiers: Int) -> String {
    if modifiers == 0x18 { return "fn" }
    var result = [String]()
    if (modifiers & 0x04) > 0 { result.append("⌃") }
    if (modifiers & 0x02) > 0 { result.append("⌥") }
    if (modifiers & 0x01) > 0 { result.append("⇧") }
    if (modifiers & 0x08) == 0 { result.append("⌘") }
    return result.joined(separator: halfWidthSpace)
}

func getShortcut(cmd: String?, modifiers: Int, virtualKey: Int) -> String {
    var shortcut = cmd
    
    if let s = shortcut, s.unicodeScalars.first?.value == 0x7f {
        shortcut = "⌦"
    } else if let vKey = virtualKeys[virtualKey] {
        shortcut = vKey
    }
    
    let mods = decodeModifiers(modifiers)
    if let s = shortcut {
        return mods + s
    }
    return ""
}

func buildAppleScriptPath(from path: [String]) -> String {
    guard !path.isEmpty else { return "" }
    guard path.count > 1 else { return "menu bar item \"\(path[0])\" of menu bar 1" }
    
    var components = ["menu item \"\(path.last!)\""]
    
    // For nested menus, we need both "menu" and "menu item" references
    for i in stride(from: path.count - 2, through: 1, by: -1) {
        components.append("of menu \"\(path[i])\"")
        components.append("of menu item \"\(path[i])\"")
    }

    // Add the top-level menu bar reference
    components.append("of menu \"\(path[0])\"")
    components.append("of menu bar item \"\(path[0])\"")
    components.append("of menu bar 1")

    return components.joined(separator: " ")
}

func extractMenuItems(from element: AXUIElement, path: [String] = [], pathIndices: String = "", depth: Int = 0) -> [MenuItem] {
    guard depth < 5 else { return [] }
    guard let children = getAttribute(element: element, name: kAXChildrenAttribute) as? [AXUIElement] else { return [] }
    
    var items: [MenuItem] = []
    
    for (i, child) in children.enumerated() {
        guard let title = getAttribute(element: child, name: kAXTitleAttribute) as? String,
              !title.isEmpty else { continue }
        
        let menuPath = path + [title.trimmingCharacters(in: .whitespacesAndNewlines)]
        
        if menuPath.first == "Apple" { continue }  // Filter out Apple menu

        let indices = pathIndices.isEmpty ? "\(i)" : "\(pathIndices),\(i)"
        
        let childElements = getAttribute(element: child, name: kAXChildrenAttribute) as? [AXUIElement] ?? []
        
        if childElements.count == 1 {
            // Submenu
            items.append(contentsOf: extractMenuItems(from: childElements[0], path: menuPath, pathIndices: indices, depth: depth + 1))
        } else {

            let enabled = getAttribute(element: child, name: kAXEnabledAttribute) as? Bool ?? false
            guard enabled else { continue } // Filter out disabled menus
            
            let cmd = getAttribute(element: child, name: kAXMenuItemCmdCharAttribute) as? String
            
            var modifiers = 0
            if let m = getAttribute(element: child, name: kAXMenuItemCmdModifiersAttribute) {
                CFNumberGetValue((m as! CFNumber), .longType, &modifiers)
            }
            
            var virtualKey = 0
            if let v = getAttribute(element: child, name: kAXMenuItemCmdVirtualKeyAttribute) {
                CFNumberGetValue((v as! CFNumber), .longType, &virtualKey)
            }
            
            let shortcut = getShortcut(cmd: cmd, modifiers: modifiers, virtualKey: virtualKey)
            let applescriptPath = buildAppleScriptPath(from: menuPath)
            
            items.append(MenuItem(
                path: menuPath,
                pathIndices: indices,
                shortcut: shortcut,
                applescriptPath: applescriptPath
            ))
        }
    }
    
    return items
}

// MARK: - Main Logic

func run() {
    let app: NSRunningApplication
    
    let args = CommandLine.arguments
    if args.count > 1 {
        let bundleId = args[1]
        guard let targetApp = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleId }) else {
            print(#"{"items": [{"title": "App Not Found", "subtitle": "Could not find running app with bundle ID: \#(bundleId)"}]}"#)
            return
        }
        app = targetApp
    } else {
        var frontApp: NSRunningApplication?
        
        frontApp = NSWorkspace.shared.menuBarOwningApplication
        
        if frontApp == nil {
            frontApp = NSWorkspace.shared.frontmostApplication
        }

        guard let frontApp = frontApp else {
            print(#"{"items": [{"title": "No active application", "subtitle": "Could not detect active application"}]}"#)
            return
        }
        app = frontApp
    }
    
    let appPath = app.bundleURL?.path ?? app.executableURL?.path ?? "icon.png"
    
    let axApp = AXUIElementCreateApplication(app.processIdentifier)
    var menuBarValue: CFTypeRef?
    let axResult = AXUIElementCopyAttributeValue(axApp, kAXMenuBarAttribute as CFString, &menuBarValue)
    
    guard axResult == .success, let menuBar = menuBarValue else {
        print(#"{"items": [{"title": "Accessibility Error", "subtitle": "Cannot access menu bar. Enable accessibility for Alfred in System Preferences."}]}"#)
        return
    }
    
    let items = extractMenuItems(from: menuBar as! AXUIElement)
    
    let alfredItems = items.map { item in
        // Create a consistent hash for Alfred's learning by using a custom hash function
        let pathString = item.path.joined(separator: ">")
        let uid = String(abs(pathString.djb2Hash))
        let title = item.shortcut.isEmpty ? item.title : "\(item.title) \t (\(item.shortcut))"
        let autocomplete = item.title
        let arg = item.applescriptPath
        let subtitle = item.subtitle
        let match = item.path.joined(separator: " ")
        let icon = [
            "type": "fileicon",
            "path": appPath
        ]
        
        return AlfredItem(
            uid: uid,
            title: title,
            autocomplete: autocomplete,
            arg: arg,
            subtitle: subtitle,
            match: match,
            icon: icon
        )
    }
    
    let jsonResult: [String: Any] = [
        "items": alfredItems.map { $0.dictionary }
    ]
    
    if let jsonData = try? JSONSerialization.data(withJSONObject: jsonResult, options: []),
       let jsonString = String(data: jsonData, encoding: .utf8) {
        print(jsonString)
    } else {
        print(#"{"items": []}"#)
    }
}

run()
