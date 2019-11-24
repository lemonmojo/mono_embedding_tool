//
//  main.swift
//  mono_embedding_tool
//
//  Created by Felix Deimel on 24.11.19.
//  Copyright © 2019 Felix Deimel. All rights reserved.
//

import Foundation

extension String {
    func lastPathComponent() -> String {
        let nsStr = self as NSString
        return nsStr.lastPathComponent
    }
    
    func appendingPathComponent(path: String) -> String {
        let nsStr = self as NSString
        return nsStr.appendingPathComponent(path)
    }
    
    func expandingTildeInPath() -> String {
        let nsStr = self as NSString
        return nsStr.expandingTildeInPath
    }
    
    func abbreviatingWithTildeInPath() -> String {
        let nsStr = self as NSString
        return nsStr.abbreviatingWithTildeInPath
    }
    
    func resolvingSylinksInPath() -> String {
        let nsStr = self as NSString
        return nsStr.resolvingSymlinksInPath
    }
    
    func deletingLastPathComponent() -> String {
        let nsStr = self as NSString
        return nsStr.deletingLastPathComponent
    }
    
    func contains(string otherString: String, caseSensitive: Bool = true) -> Bool {
        return self.range(of: otherString, options: caseSensitive ? [] : [.caseInsensitive], range: nil, locale: nil) != nil
    }
    
    func fileURLFromPath() -> URL {
        let fileURL = URL.init(fileURLWithPath: self)
        
        return fileURL
    }
    
    func isDLLFile() -> Bool {
        let fileExtension = self.fileURLFromPath().pathExtension.lowercased()
        
        return fileExtension.hasSuffix("dll")
    }
    
    func isDylibFile() -> Bool {
        let fileExtension = self.fileURLFromPath().pathExtension.lowercased()
        
        return fileExtension.hasSuffix("dylib")
    }
    
    func directoryExists() -> Bool {
        var isDirectory = ObjCBool(true)
        let exists = FileManager.default.fileExists(atPath: self, isDirectory: &isDirectory)
        
        return exists && isDirectory.boolValue
    }
}

class ConsoleIO {
    enum OutputType {
        case error
        case standard
    }
    
    static func printMessage(_ message: String, to: OutputType = .standard) {
        switch to {
        case .standard:
            print("\(message)")
        case .error:
            fputs("Error: \(message)\n", stderr)
        }
    }
}

class FileCollector {
    var systemMonoPath: String
    var blacklistedFilenames: [String]
    
    init(systemMonoPath: String) {
        self.systemMonoPath = systemMonoPath
        self.blacklistedFilenames = [String]()
    }
    
    func pathsOfCollectedFilesRelativeToSystemMonoPath() -> [String] {
        var collectedRelativePaths = [String]()
        
        let machineConfigPath = "/etc/mono/4.5/machine.config"
        
        collectedRelativePaths.append(machineConfigPath)
        
        let libPath = "/lib"
        
        let libmonosgenPath = libPath.appendingPathComponent(path: "libmonosgen-2.0.dylib")
        
        collectedRelativePaths.append(libmonosgenPath)
        
        let libmononativecompatPath = libPath.appendingPathComponent(path: "libmono-native-compat.0.dylib")
        
        collectedRelativePaths.append(libmononativecompatPath)
        
        let libMonoPosixHelperPath = libPath.appendingPathComponent(path: "libMonoPosixHelper.dylib")
        
        collectedRelativePaths.append(libMonoPosixHelperPath)
        
        let libMonoPath = libPath.appendingPathComponent(path: "/mono")
        //let fullLibMonoPath = self.systemMonoPath.appendingPathComponent(path: libMonoPath)
        
        let libMono45Path = libMonoPath.appendingPathComponent(path: "4.5")
        let fullLibMono45Path = self.systemMonoPath.appendingPathComponent(path: libMono45Path)
        
        let fileManager = FileManager.default
        
        let enumOpts: FileManager.DirectoryEnumerationOptions = [.producesRelativePathURLs,
                                                                 .skipsSubdirectoryDescendants,
                                                                 .skipsPackageDescendants,
                                                                 .skipsHiddenFiles]
        
        let contents = try? fileManager.contentsOfDirectory(at: URL.init(fileURLWithPath: fullLibMono45Path),
                                                            includingPropertiesForKeys: nil,
                                                            options: enumOpts)
        
        if let contents = contents {
            for fileURL in contents {
                let fileExtension = fileURL.pathExtension
                
                if !fileExtension.hasSuffix("dll") {
                    continue
                }
                
                let fileName = fileURL.relativePath
                
                let isBlacklisted = isFileNameBlacklisted(fileName: fileName)
                
                if isBlacklisted {
                    continue
                }
                
                let relativeFilePath = libMono45Path.appendingPathComponent(path: fileName)
                
                collectedRelativePaths.append(relativeFilePath)
            }
        }
        
        return collectedRelativePaths
    }
    
    func isFileNameBlacklisted(fileName: String) -> Bool {
        for blacklistedItem in self.blacklistedFilenames {
            if fileName.contains(string: blacklistedItem, caseSensitive: false) {
                return true
            }
        }
        
        return false
    }
}

class MonoCopier {
    var systemMonoPath: String
    let relativeFilePathsToCopy: [String]
    let outputPath: String
    
    let infoPlistContent = """
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>Versions/Current/lib/libmonosgen-2.0.dylib</string>
    <key>CFBundleIdentifier</key>
    <string>com.lemonmojo.Mono</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Mono</string>
    <key>CFBundlePackageType</key>
    <string>FMWK</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleSupportedPlatforms</key>
    <array>
        <string>MacOSX</string>
    </array>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2019 Felix Deimel. All rights reserved.</string>
</dict>
</plist>
"""
    
    init(systemMonoPath: String, relativeFilePathsToCopy: [String], outputPath: String) {
        self.systemMonoPath = systemMonoPath
        self.relativeFilePathsToCopy = relativeFilePathsToCopy
        self.outputPath = outputPath
    }
    
    func copy() -> Bool {
        let fileManager = FileManager.default
        
        if self.outputPath.directoryExists() {
            do {
                try fileManager.removeItem(atPath: self.outputPath)
            } catch {
                ConsoleIO.printMessage("Failed to delete output directory", to: .error)
                
                return false
            }
        }
        
        do {
            try fileManager.createDirectory(atPath: self.outputPath, withIntermediateDirectories: true, attributes: nil)
        } catch {
            ConsoleIO.printMessage("Failed to create output directory", to: .error)
            
            return false
        }
        
        let outputVersionAPath = self.outputPath.appendingPathComponent(path: "Versions").appendingPathComponent(path: "A")
        
        do {
            try fileManager.createDirectory(atPath: outputVersionAPath, withIntermediateDirectories: true, attributes: nil)
        } catch {
            ConsoleIO.printMessage("Failed to create Versions/A directory", to: .error)
            
            return false
        }
        
        let outputVersionAResourcesPath = outputVersionAPath.appendingPathComponent(path: "Resources")
        
        do {
            try fileManager.createDirectory(atPath: outputVersionAResourcesPath, withIntermediateDirectories: true, attributes: nil)
        } catch {
            ConsoleIO.printMessage("Failed to create Versions/A/Resources directory", to: .error)
            
            return false
        }
        
        let infoPlistPath = outputVersionAResourcesPath.appendingPathComponent(path: "Info.plist")
        
        do {
            try self.infoPlistContent.write(toFile: infoPlistPath, atomically: true, encoding: .utf8)
        } catch {
            ConsoleIO.printMessage("Failed to create Info.plist in Resources directory", to: .error)
            
            return false
        }
        
        let outputResourcesPath = self.outputPath.appendingPathComponent(path: "Resources")
        let versionsCurrentResourcesRelativePath = "Versions/Current/Resources"
        
        do {
            try fileManager.createSymbolicLink(atPath: outputResourcesPath, withDestinationPath: versionsCurrentResourcesRelativePath)
        } catch {
            ConsoleIO.printMessage("Failed create symlink for \(versionsCurrentResourcesRelativePath) at \(outputResourcesPath)", to: .error)
            
            return false
        }
        
        let libPath = outputVersionAPath.appendingPathComponent(path: "lib")
        
        for relativeFilePath in self.relativeFilePathsToCopy {
            let absoluteFilePath = self.systemMonoPath.appendingPathComponent(path: relativeFilePath)
            let resolvedAbsoluteFilePath = absoluteFilePath.resolvingSylinksInPath()
            
            ConsoleIO.printMessage("Going to copy \(resolvedAbsoluteFilePath)...")
            
            if relativeFilePath.isDLLFile() { // Put symlinks for all DLLs into lib root folder
                let dllFileName = relativeFilePath.lastPathComponent()
                let symlinkPath = libPath.appendingPathComponent(path: dllFileName)
                
                var symlinkDestinationPath = relativeFilePath
                
                if relativeFilePath.starts(with: "/lib/") {
                    symlinkDestinationPath = String(relativeFilePath[relativeFilePath.range(of: "/lib/")!.upperBound...])
                }
                
                do {
                    try fileManager.createSymbolicLink(atPath: symlinkPath, withDestinationPath: symlinkDestinationPath)
                } catch {
                    ConsoleIO.printMessage("Failed create symlink for \(relativeFilePath) at \(symlinkPath)", to: .error)
                    
                    return false
                }
            }
            
            let absoluteDestinationPath = outputVersionAPath.appendingPathComponent(path: relativeFilePath)
            
            /* let rangeOfSystemMonoPath = resolvedAbsoluteFilePath.range(of: self.systemMonoPath.resolvingSylinksInPath())
            
            if let rangeOfSystemMonoPath = rangeOfSystemMonoPath {
                let newRelativeFilePath = String(resolvedAbsoluteFilePath[rangeOfSystemMonoPath.upperBound...])
                
                absoluteDestinationPath = outputVersionAPath.appendingPathComponent(path: newRelativeFilePath)
            } */
            
            let absoluteDestinationDirectoryPath = absoluteDestinationPath.deletingLastPathComponent()
            
            if !absoluteDestinationDirectoryPath.directoryExists() {
                do {
                    try fileManager.createDirectory(atPath: absoluteDestinationDirectoryPath, withIntermediateDirectories: true, attributes: nil)
                } catch {
                    ConsoleIO.printMessage("Failed to create directory at \(absoluteDestinationDirectoryPath)", to: .error)
                    
                    return false
                }
            }
            
            do {
                try fileManager.copyItem(atPath: resolvedAbsoluteFilePath, toPath: absoluteDestinationPath)
            } catch {
                ConsoleIO.printMessage("Failed to create copy file from \(resolvedAbsoluteFilePath)", to: .error)
                
                return false
            }
            
            if !processCopiedFile(copiedFilePath: absoluteDestinationPath) {
                ConsoleIO.printMessage("Failed to process copied file \(absoluteDestinationPath)", to: .error)
                
                return false
            }
        }
        
        let libmonosgenFilename = "libmonosgen-2.0.dylib"
        let libmonosgenPath = libPath.appendingPathComponent(path: libmonosgenFilename)
        
        if !changeDylibID(of: libmonosgenPath, to: newDylibID(for: libmonosgenFilename)) {
            return false
        }
        
        let libMonoPosixHelperFilename = "libMonoPosixHelper.dylib"
        let libMonoPosixHelperPath = libPath.appendingPathComponent(path: libMonoPosixHelperFilename)
        
        if !changeDylibID(of: libMonoPosixHelperPath, to: newDylibID(for: libMonoPosixHelperFilename)) {
            return false
        }
        
        let libMonoNativeCompatFilename = "libmono-native-compat.0.dylib"
        let libMonoNativeCompatPath = libPath.appendingPathComponent(path: libMonoNativeCompatFilename)
        let libSystemNativeFilename = "libSystem.Native.dylib"
        let libSystemNativePath = libPath.appendingPathComponent(path: "mono").appendingPathComponent(path: "4.5").appendingPathComponent(path: libSystemNativeFilename)
        
        do {
            try fileManager.moveItem(atPath: libMonoNativeCompatPath, toPath: libSystemNativePath)
        } catch {
            ConsoleIO.printMessage("Failed to rename \(libMonoNativeCompatFilename) to \(libSystemNativeFilename)", to: .error)
            
            return false
        }
        
        if !changeDylibID(of: libSystemNativePath, to: newDylibID(for: libSystemNativeFilename)) {
            return false
        }
        
        let outputVersionCurrentPath = self.outputPath.appendingPathComponent(path: "Versions").appendingPathComponent(path: "Current")
        let versionARelativePath = "A";
        
        do {
            try fileManager.createSymbolicLink(atPath: outputVersionCurrentPath, withDestinationPath: versionARelativePath)
        } catch {
            ConsoleIO.printMessage("Failed create symlink for \(versionARelativePath) at \(outputVersionCurrentPath)", to: .error)
            
            return false
        }
        
        let mainFrameworkSymlinkInVersionAPath = outputVersionAPath.appendingPathComponent(path: "Mono")
        let libmonosgenInLibPath = "lib".appendingPathComponent(path: libmonosgenFilename)
        
        do {
            try fileManager.createSymbolicLink(atPath: mainFrameworkSymlinkInVersionAPath, withDestinationPath: libmonosgenInLibPath)
        } catch {
            ConsoleIO.printMessage("Failed create symlink for \(libmonosgenInLibPath) at \(mainFrameworkSymlinkInVersionAPath)", to: .error)
            
            return false
        }
        
        let mainFrameworkBinarySymlinkPath = self.outputPath.appendingPathComponent(path: "Mono")
        let libmonosgenInCurrentVersionPath = "Versions".appendingPathComponent(path: "Current").appendingPathComponent(path: "Mono")
        
        do {
            try fileManager.createSymbolicLink(atPath: mainFrameworkBinarySymlinkPath, withDestinationPath: libmonosgenInCurrentVersionPath)
        } catch {
            ConsoleIO.printMessage("Failed create symlink for \(libmonosgenInCurrentVersionPath) at \(mainFrameworkBinarySymlinkPath)", to: .error)
            
            return false
        }
        
        return true
    }
    
    func newDylibID(for fileName: String) -> String {
        return "@rpath/Mono.framework/Versions/Current/lib/\(fileName)"
    }
    
    func processCopiedFile(copiedFilePath: String) -> Bool {
        if copiedFilePath.isDylibFile() {
            if !stripAllArchitectures(except: "x86_64", of: copiedFilePath) {
                return false
            }
        }
        
        return true
    }
    
    func runProcess(launchPath: String, arguments: [String]) -> Bool {
        let proc = Process()
        
        proc.launchPath = launchPath
        proc.arguments = arguments
        
        proc.launch()
        proc.waitUntilExit()
        
        let success = proc.terminationStatus == 0
        
        return success
    }
    
    func stripAllArchitectures(except targetArchitecture: String, of filePath: String) -> Bool {
        ConsoleIO.printMessage("Stripping binary \(filePath) down to \(targetArchitecture) architecture...");
        
        let dittoPath = "/usr/bin/ditto"
        let tempFilePath = filePath + "_TEMP"
        
        let success = runProcess(launchPath: dittoPath, arguments: [
            "--rsrc",
            "--arch",
            targetArchitecture,
            
            filePath,
            tempFilePath
        ])
        
        if !success {
            ConsoleIO.printMessage("Failed to strip Binary \(filePath) down to \(targetArchitecture) architecture", to: .error);
            
            return false
        }
        
        let fileManager = FileManager.default
        
        do {
            try fileManager.removeItem(atPath: filePath)
        } catch {
            ConsoleIO.printMessage("Failed to delete copied file from \(filePath)", to: .error)
            
            return false
        }
        
        do {
            try fileManager.moveItem(atPath: tempFilePath, toPath: filePath)
        } catch {
            ConsoleIO.printMessage("Failed to move copied file from \(tempFilePath) to \(filePath)", to: .error)
            
            return false
        }
        
        return true
    }
    
    func changeDylibID(of filePath: String, to newID: String) -> Bool {
        ConsoleIO.printMessage("Changing ID of Dylib \(filePath) to \(newID)...");
        
        let installNameToolPath = "/usr/bin/install_name_tool"
        
        let success = runProcess(launchPath: installNameToolPath, arguments: [
            "-id",
            newID,
            
            filePath
        ])
        
        if !success {
            ConsoleIO.printMessage("Failed to change ID of Dylib \(filePath) to \(newID)", to: .error);
            
            return false
        }
        
        return true
    }
}

let systemMonoPath = CommandLine.arguments[1].expandingTildeInPath()
let outputPath = CommandLine.arguments[2].expandingTildeInPath()

let fileCollector = FileCollector(systemMonoPath: systemMonoPath)

fileCollector.blacklistedFilenames = [
    "Accessibility.dll",
    "Commons.Xml.Relaxng.dll",
    "Microsoft.Visual",
    "Microsoft.Build",
    "Mono",
    "Reactive",
    "Razor",
    "Oracle",
    "System.Windows.Forms.DataVisualization",
    "System.Xaml",
    "CodeAnalysis",
    "IBM",
    "RabbitMQ",
    "WindowsBase",
    "SMDiagnostics.dll",
    "ICSharpCode.SharpZipLib.dll",
    "PEAPI.dll",
    "cscompmgd.dll",
    "System.Data.Entity.dll",
    "Novell.Directory.Ldap",
    "WebMatrix.Data.dll",
    "System.Web.Mvc.dll"
]

let relativePaths = fileCollector.pathsOfCollectedFilesRelativeToSystemMonoPath()

let monoCopier = MonoCopier(systemMonoPath: systemMonoPath,
                            relativeFilePathsToCopy: relativePaths,
                            outputPath: outputPath)

let success = monoCopier.copy()

let outputPathForDisplay = outputPath.abbreviatingWithTildeInPath()

if success {
    ConsoleIO.printMessage("Successfully created embeddable Mono framework at \(outputPathForDisplay)")
} else {
    ConsoleIO.printMessage("Failed to create embeddable Mono framework at \(outputPathForDisplay)", to: .error)
}

