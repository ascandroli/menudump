#!/usr/bin/env swift

import Foundation

struct MenuItem {
    let path: [String]
    let shortcut: String
}

struct AppInfo {
    let name: String
    let bundleIdentifier: String
}

func generateMarkdown(appInfo: AppInfo, menuItems: [MenuItem]) -> String {
    var markdown = """
# \(appInfo.name)

**Bundle ID:** `\(appInfo.bundleIdentifier)`

---

"""
    
    var groupedMenus: [String: [MenuItem]] = [:]
    for item in menuItems {
        guard !item.shortcut.isEmpty else { continue }
        let topMenu = item.path.first ?? "Other"
        if groupedMenus[topMenu] == nil {
            groupedMenus[topMenu] = []
        }
        groupedMenus[topMenu]?.append(item)
    }
    
    let sortedMenus = groupedMenus.keys.sorted()
    for menuName in sortedMenus {
        guard let items = groupedMenus[menuName], !items.isEmpty else { continue }
        
        markdown += """

## \(menuName)

"""
        
        for item in items {
            let menuPath = item.path.dropFirst().joined(separator: " → ")
            let displayText = menuPath.isEmpty ? item.path.last ?? "" : menuPath
            markdown += "- **\(item.shortcut)** — `\(displayText)`\n"
        }
    }
    
    return markdown
}

func processYAMLData(_ yamlString: String) -> (AppInfo?, [MenuItem]) {
    let lines = yamlString.components(separatedBy: .newlines)
    var appName = ""
    var bundleIdentifier = ""
    var menuItems: [MenuItem] = []
    
    var inMenus = false
    var currentPath: [String] = []
    var currentShortcut = ""
    
    for line in lines {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        
        if trimmed.hasPrefix("name: ") {
            appName = trimmed.replacingOccurrences(of: "name: ", with: "").trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        } else if trimmed.hasPrefix("bundleIdentifier: ") {
            bundleIdentifier = trimmed.replacingOccurrences(of: "bundleIdentifier: ", with: "").trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        } else if trimmed == "menus:" {
            inMenus = true
        } else if inMenus {
            if trimmed.hasPrefix("- path: [") {
                // Parse path array
                let pathString = trimmed.replacingOccurrences(of: "- path: [", with: "").replacingOccurrences(of: "]", with: "")
                currentPath = pathString.components(separatedBy: ", ").map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\"")) }
            } else if trimmed.hasPrefix("shortcut: ") {
                currentShortcut = trimmed.replacingOccurrences(of: "shortcut: ", with: "").trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                if !currentShortcut.isEmpty {
                    menuItems.append(MenuItem(path: currentPath, shortcut: currentShortcut))
                }
                currentPath = []
                currentShortcut = ""
            }
        }
    }
    
    let appInfo = AppInfo(name: appName, bundleIdentifier: bundleIdentifier)
    return (appInfo, menuItems)
}

func main() {
    var yamlString = ""
    while let line = readLine() {
        yamlString += line + "\n"
    }
    
    guard !yamlString.isEmpty else {
        print("Error: No YAML input received")
        exit(1)
    }
    
    let (appInfo, menuItems) = processYAMLData(yamlString)
    
    guard let appInfo = appInfo else {
        print("Error: Could not parse app information from YAML")
        exit(1)
    }
    
    let markdown = generateMarkdown(appInfo: appInfo, menuItems: menuItems)
    print(markdown)
}

main()
