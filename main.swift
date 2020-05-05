//
//  main.swift
//  mono_embedding_tool
//
//  Created by Felix Deimel on 24.11.19.
//  Copyright © 2020 Felix Deimel. All rights reserved.
//

import Foundation
import zlib

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
	
	func replacingFirstOccurrence(of target: String, with replacementString: String) -> String {
        if let range = self.range(of: target) {
            return self.replacingCharacters(in: range, with: replacementString)
        }
		
        return self
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
    
    func isWritablePath() -> Bool {
        return FileManager.default.isWritableFile(atPath: self)
    }
}

extension Data {
    var isGzipped: Bool {
        return self.starts(with: [0x1f, 0x8b])  // check magic number
    }
    
    public func gzipped(level: Int32 = Z_DEFAULT_COMPRESSION) -> Data? {
        
        guard !self.isEmpty else {
            return Data()
        }
        
        var stream = z_stream()
        var status: Int32
        
        let streamSize = MemoryLayout<z_stream>.size
        let chunk = 1 << 14
        
        status = deflateInit2_(&stream, level, Z_DEFLATED, MAX_WBITS + 16, MAX_MEM_LEVEL, Z_DEFAULT_STRATEGY, ZLIB_VERSION, Int32(streamSize))
        
        guard status == Z_OK else {
            // deflateInit2 returns:
            // Z_VERSION_ERROR  The zlib library version is incompatible with the version assumed by the caller.
            // Z_MEM_ERROR      There was not enough memory.
            // Z_STREAM_ERROR   A parameter is invalid.
            
            return nil
        }
        
        var data = Data(capacity: chunk)
        repeat {
            if Int(stream.total_out) >= data.count {
                data.count += chunk
            }
            
            let inputCount = self.count
            let outputCount = data.count
            
            self.withUnsafeBytes { (inputPointer: UnsafeRawBufferPointer) in
                stream.next_in = UnsafeMutablePointer<Bytef>(mutating: inputPointer.bindMemory(to: Bytef.self).baseAddress!).advanced(by: Int(stream.total_in))
                stream.avail_in = uint(inputCount) - uInt(stream.total_in)
                
                data.withUnsafeMutableBytes { (outputPointer: UnsafeMutableRawBufferPointer) in
                    stream.next_out = outputPointer.bindMemory(to: Bytef.self).baseAddress!.advanced(by: Int(stream.total_out))
                    stream.avail_out = uInt(outputCount) - uInt(stream.total_out)
                    
                    status = deflate(&stream, Z_FINISH)
                    
                    stream.next_out = nil
                }
                
                stream.next_in = nil
            }
            
        } while stream.avail_out == 0
        
        guard deflateEnd(&stream) == Z_OK, status == Z_STREAM_END else {
            return nil
        }
        
        data.count = Int(stream.total_out)
        
        return data
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
    
    static func printUsage(_ usageInstructions: String) {
        fputs("Usage: \(usageInstructions)\n", stderr)
    }
}

class FileCollector {
    let systemMonoPath: String
    let blacklistedFilenames: [String]
    
    init(systemMonoPath: String, blacklistedFilenames: [String] = [String]()) {
        self.systemMonoPath = systemMonoPath
        self.blacklistedFilenames = blacklistedFilenames
    }
    
    func pathsOfCollectedFilesRelativeToSystemMonoPath() -> [String] {
        var collectedRelativePaths = [String]()
        
        let machineConfigPath = "/etc/mono/4.5/machine.config"
        
        collectedRelativePaths.append(machineConfigPath)
        
        let libPath = "/lib"
        
        let libmonosgenPath = libPath.appendingPathComponent(path: "libmonosgen-2.0.dylib")
        collectedRelativePaths.append(libmonosgenPath)
        
		/* let libintlPath = libPath.appendingPathComponent(path: "libintl.8.dylib")
        collectedRelativePaths.append(libintlPath) */
		
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
		
		let libMono45FacadesPath = "Facades"
		let netstandardPath = libMono45FacadesPath.appendingPathComponent(path: "netstandard.dll")
		
		let customIncludes = [
			netstandardPath.fileURLFromPath()
		]
		
		for fileURL in customIncludes {
			collect(fromURL: fileURL, relativePathRoot: libMono45Path, collection: &collectedRelativePaths)
		}
        
        if let contents = contents {
            for fileURL in contents {
                collect(fromURL: fileURL, relativePathRoot: libMono45Path, collection: &collectedRelativePaths)
            }
        }
        
        return collectedRelativePaths
    }
	
	func collect(fromURL fileURL: URL, relativePathRoot: String, collection: inout [String]) {
		let fileExtension = fileURL.pathExtension
		
		if !fileExtension.hasSuffix("dll") {
			return
		}
		
		let fileName = fileURL.relativePath
		
		let isBlacklisted = isFileNameBlacklisted(fileName: fileName)
		
		if isBlacklisted {
			return
		}
		
		let relativeFilePath = relativePathRoot.appendingPathComponent(path: fileName)
		
		collection.append(relativeFilePath)
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

struct CompressedMetaData: Codable {
    let name: String
    let offset: Int
    let size: Int
}

class MonoAssemblyDecompressionUtils {
    private static let metaDatasToken = "$$$$METADATAS$$$$"
    
    private static let headerContent = """
#ifndef Mono_h
#define Mono_h

#import <Foundation/Foundation.h>
#import <zlib.h>

@interface METCompressedAssemblyMetaData : NSObject

@property (copy) NSString* name;
@property (assign) NSInteger offset;
@property (assign) NSInteger size;

- (instancetype)initWithName:(NSString*)name offset:(NSInteger)offset size:(NSInteger)size;
+ (instancetype)metaDataWithName:(NSString*)name offset:(NSInteger)offset size:(NSInteger)size;

@end

@implementation METCompressedAssemblyMetaData

- (instancetype)initWithName:(NSString *)name offset:(NSInteger)offset size:(NSInteger)size {
    self = [super init];
    
    if (self) {
        self.name = name;
        self.offset = offset;
        self.size = size;
    }
    
    return self;
}

+ (instancetype)metaDataWithName:(NSString *)name offset:(NSInteger)offset size:(NSInteger)size {
    return [[METCompressedAssemblyMetaData alloc] initWithName:name offset:offset size:size];
}

@end


@interface METAssemblyDecompressor: NSObject

+ (NSData*)decompressedDataOfAssemblyWithName:(NSString*)name inMonoFrameworkBundle:(NSBundle*)bundle;
+ (NSDictionary<NSString*, NSData*>*)decompressedDataOfAllAssembliesInMonoFrameworkBundle:(NSBundle*)bundle;

@end


@implementation METAssemblyDecompressor

static NSDictionary<NSString*, METCompressedAssemblyMetaData*>* metaDatas;

+ (void)initialize {
    static dispatch_once_t onceToken;
    
    dispatch_once(&onceToken, ^{
        metaDatas = @{
$$$$METADATAS$$$$
        };
    });
}

+ (NSData*)gunzippedDataWithData:(NSData*)data {
    if (data.length == 0) {
        return data;
    }
    
    const UInt8 *bytes = (const UInt8 *)data.bytes;
    
    if (!(data.length >= 2 && bytes[0] == 0x1f && bytes[1] == 0x8b)) {
        // Is not gzipped
        return data;
    }

    z_stream stream;
    stream.zalloc = Z_NULL;
    stream.zfree = Z_NULL;
    stream.avail_in = (uint)data.length;
    stream.next_in = (Bytef *)data.bytes;
    stream.total_out = 0;
    stream.avail_out = 0;

    NSMutableData *output = nil;
    
    if (inflateInit2(&stream, 47) == Z_OK) {
        int status = Z_OK;
        output = [NSMutableData dataWithCapacity:data.length * 2];
        
        while (status == Z_OK) {
            if (stream.total_out >= output.length) {
                output.length += data.length / 2;
            }
            stream.next_out = (uint8_t *)output.mutableBytes + stream.total_out;
            stream.avail_out = (uInt)(output.length - stream.total_out);
            status = inflate (&stream, Z_SYNC_FLUSH);
        }
        
        if (inflateEnd(&stream) == Z_OK) {
            if (status == Z_STREAM_END) {
                output.length = stream.total_out;
            }
        }
    }

    return output;
}

+ (NSData*)decompressedDataOfAssemblyWithMetaData:(METCompressedAssemblyMetaData*)metaData inBinData:(NSData*)binData {
    if (!metaData ||
        !binData) {
        return nil;
    }
    
    NSData* compressedData = [binData subdataWithRange:NSMakeRange(metaData.offset, metaData.size)];
    NSData* data = [self gunzippedDataWithData:compressedData];
    
    return data;
}

+ (NSData*)binDataWithMonoFrameworkBundle:(NSBundle*)bundle {
    if (!bundle) {
        return nil;
    }
    
    NSString* bundlePath = bundle.bundlePath;
    
    NSString* libPath = [[bundlePath stringByAppendingPathComponent:@"/Versions/Current/lib"] stringByResolvingSymlinksInPath];
    NSString* binFileName = @"Assemblies.bin";
    
    NSString* binFilePath = [libPath stringByAppendingPathComponent:binFileName];
    
    NSData* binData = [NSData dataWithContentsOfFile:binFilePath];
    
    return binData;
}

+ (NSData*)decompressedDataOfAssemblyWithName:(NSString*)name inMonoFrameworkBundle:(NSBundle*)bundle {
    if (!bundle) {
        return nil;
    }
    
    METCompressedAssemblyMetaData* metaData = metaDatas[name];
    
    if (!metaData) {
        return nil;
    }
    
    NSData* binData = [self binDataWithMonoFrameworkBundle:bundle];
    
    NSData* data = [self decompressedDataOfAssemblyWithMetaData:metaData inBinData:binData];
    
    return data;
}

+ (NSDictionary<NSString*, NSData*>*)decompressedDataOfAllAssembliesInMonoFrameworkBundle:(NSBundle*)bundle {
    if (!bundle) {
        return nil;
    }
    
    NSMutableDictionary<NSString*, NSData*>* datas = NSMutableDictionary.dictionary;
    
    NSData* binData = [self binDataWithMonoFrameworkBundle:bundle];
    
    if (!binData) {
        return nil;
    }
    
    [metaDatas enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull name, METCompressedAssemblyMetaData * _Nonnull metaData, BOOL * _Nonnull stop) {
        NSData* data = [self decompressedDataOfAssemblyWithMetaData:metaData inBinData:binData];
        
        datas[metaData.name] = data;
    }];
    
    return datas;
}

@end

#endif /* Mono_h */
"""
    
    static func headerContent(metaDatas: [CompressedMetaData]) -> String {
        var metaDatasStr = ""
        
        for metaData in metaDatas {
            metaDatasStr.append("            @\"\(metaData.name)\": [METCompressedAssemblyMetaData metaDataWithName:@\"\(metaData.name)\" offset:\(metaData.offset) size:\(metaData.size)],\n")
        }
        
        let content = self.headerContent.replacingOccurrences(of: self.metaDatasToken, with: metaDatasStr)
        
        return content
    }
}

class MonoCopier {
    var systemMonoPath: String
    let relativeFilePathsToCopy: [String]
    let outputPath: String
    let compress: Bool
	
	let installNameToolPath = "/usr/bin/install_name_tool"
	let otoolPath = "/usr/bin/otool"
    
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
    <string>Copyright © 2020 Felix Deimel. All rights reserved.</string>
</dict>
</plist>
"""
    
    init(systemMonoPath: String, relativeFilePathsToCopy: [String], outputPath: String, compress: Bool) {
        self.systemMonoPath = systemMonoPath
        self.relativeFilePathsToCopy = relativeFilePathsToCopy
        self.outputPath = outputPath
        self.compress = compress
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
        
        let outputVersionAHeadersPath = outputVersionAPath.appendingPathComponent(path: "Headers")
        
        do {
            try fileManager.createDirectory(atPath: outputVersionAHeadersPath, withIntermediateDirectories: true, attributes: nil)
        } catch {
            ConsoleIO.printMessage("Failed to create Versions/A/Headers directory", to: .error)
            
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
        
        let libPath = outputVersionAPath.appendingPathComponent(path: "lib")
        
        var compressedMetaDatas = [CompressedMetaData]()
        var compressedDataOffset = 0
        var compressedDataBlock = Data()
        
        for relativeFilePath in self.relativeFilePathsToCopy {
            let absoluteFilePath = self.systemMonoPath.appendingPathComponent(path: relativeFilePath)
            let resolvedAbsoluteFilePath = absoluteFilePath.resolvingSylinksInPath()
            
            ConsoleIO.printMessage("Copying \(resolvedAbsoluteFilePath)...")
            
            let isDLLFile = relativeFilePath.isDLLFile()
            
            if !compress && isDLLFile { // Put symlinks for all DLLs into lib root folder
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
            let absoluteDestinationDirectoryPath = absoluteDestinationPath.deletingLastPathComponent()
            
            if !absoluteDestinationDirectoryPath.directoryExists() {
                do {
                    try fileManager.createDirectory(atPath: absoluteDestinationDirectoryPath, withIntermediateDirectories: true, attributes: nil)
                } catch {
                    ConsoleIO.printMessage("Failed to create directory at \(absoluteDestinationDirectoryPath)", to: .error)
                    
                    return false
                }
            }
            
            var shouldCopy = true
            
            if compress && isDLLFile {
                // Compress
                if let compressedData = compressedData(ofFileAtPath: resolvedAbsoluteFilePath) {
                    let fileName = resolvedAbsoluteFilePath.lastPathComponent()
                    let size = compressedData.count
                    
                    let metaData = CompressedMetaData(name: fileName, offset: compressedDataOffset, size: size)
                    
                    compressedMetaDatas.append(metaData)
                    compressedDataBlock.append(compressedData)
                    
                    compressedDataOffset += size
                    
                    shouldCopy = false
                } else {
                    ConsoleIO.printMessage("Failed to compress file from \(resolvedAbsoluteFilePath)", to: .error)
                    
                    return false
                }
            }
            
            if shouldCopy {
                do {
                    try fileManager.copyItem(atPath: resolvedAbsoluteFilePath, toPath: absoluteDestinationPath)
                } catch {
                    ConsoleIO.printMessage("Failed to create copy file from \(resolvedAbsoluteFilePath)", to: .error)
                    
                    return false
                }
            }
            
            if !processCopiedFile(copiedFilePath: absoluteDestinationPath) {
                ConsoleIO.printMessage("Failed to process copied file \(absoluteDestinationPath)", to: .error)
                
                return false
            }
        }
        
        if compress && compressedDataBlock.count > 0 {
            let compressedAssembliesFileName = "Assemblies.bin"
            let compressedAssembliesDestinationPath = libPath.appendingPathComponent(path: compressedAssembliesFileName)
            
            let compressedAssembliesHeaderFileName = "Mono.h"
            let compressedAssembliesHeaderDestinationPath = outputVersionAHeadersPath.appendingPathComponent(path: compressedAssembliesHeaderFileName)
            
            let headerContent = MonoAssemblyDecompressionUtils.headerContent(metaDatas: compressedMetaDatas)
            
            do {
                try compressedDataBlock.write(to: compressedAssembliesDestinationPath.fileURLFromPath())
                
                try headerContent.data(using: .utf8)?.write(to: compressedAssembliesHeaderDestinationPath.fileURLFromPath())
            } catch {
                return false
            }
        }
		
		/* let libintlFilename = "libintl.8.dylib"
		let libintlPath = libPath.appendingPathComponent(path: libintlFilename)
		let libintlDestinationFilename = "libintl.dylib"
		let libintlDestinationPath = libPath.appendingPathComponent(path: "mono").appendingPathComponent(path: "4.5").appendingPathComponent(path: libintlDestinationFilename)
		var oldLibintlDylibID = ""
		
		if let id = idOfDylib(at: libintlPath) {
			oldLibintlDylibID = id
		} else {
			ConsoleIO.printMessage("Failed to get ID of dylib \(libintlPath)", to: .error)
			
			return false
		}
		
		do {
            try fileManager.moveItem(atPath: libintlPath, toPath: libintlDestinationPath)
        } catch {
            ConsoleIO.printMessage("Failed to rename \(libintlFilename) to \(libintlDestinationFilename)", to: .error)
            
            return false
        }
		
		let newLibintlDylibID = newDylibID(for: "mono".appendingPathComponent(path: "4.5").appendingPathComponent(path: libintlDestinationFilename))
        
		if !changeIDOfDylib(at: libintlDestinationPath, to: newLibintlDylibID) {
            return false
        } */
		
        let libmonosgenFilename = "libmonosgen-2.0.dylib"
        let libmonosgenPath = libPath.appendingPathComponent(path: libmonosgenFilename)
        
        if !changeIDOfDylib(at: libmonosgenPath, to: newDylibID(for: libmonosgenFilename)) {
            return false
        }
		
		/* if !changeDependencyOfDylib(at: libmonosgenPath, oldDependency: oldLibintlDylibID, newDependency: newLibintlDylibID) {
			return false
		} */
        
        let libMonoPosixHelperFilename = "libMonoPosixHelper.dylib"
        let libMonoPosixHelperPath = libPath.appendingPathComponent(path: libMonoPosixHelperFilename)
        
        if !changeIDOfDylib(at: libMonoPosixHelperPath, to: newDylibID(for: libMonoPosixHelperFilename)) {
            return false
        }
		
		/* if !changeDependencyOfDylib(at: libMonoPosixHelperPath, oldDependency: oldLibintlDylibID, newDependency: newLibintlDylibID) {
			return false
		} */
        
        let libMonoNativeCompatFilename = "libmono-native-compat.0.dylib"
        let libMonoNativeCompatPath = libPath.appendingPathComponent(path: libMonoNativeCompatFilename)
        let libSystemNativeFilename = "libSystem.Native.dylib"
        let libSystemNativePath = libPath.appendingPathComponent(path: "mono").appendingPathComponent(path: "4.5").appendingPathComponent(path: libSystemNativeFilename)
        
		let libSystemNativeDirectoryPath = libSystemNativePath.deletingLastPathComponent()
		
		if !libSystemNativeDirectoryPath.directoryExists() {
			do {
				try fileManager.createDirectory(atPath: libSystemNativeDirectoryPath, withIntermediateDirectories: true, attributes: nil)
			} catch {
				ConsoleIO.printMessage("Failed to create directory at \(libSystemNativeDirectoryPath)", to: .error)
				
				return false
			}
		}
		
        do {
            try fileManager.moveItem(atPath: libMonoNativeCompatPath, toPath: libSystemNativePath)
        } catch {
            ConsoleIO.printMessage("Failed to rename \(libMonoNativeCompatFilename) to \(libSystemNativeFilename)", to: .error)
            
            return false
        }
        
        if !changeIDOfDylib(at: libSystemNativePath, to: newDylibID(for: "mono".appendingPathComponent(path: "4.5").appendingPathComponent(path: libSystemNativeFilename))) {
            return false
        }
		
		/* if !changeDependencyOfDylib(at: libSystemNativePath, oldDependency: oldLibintlDylibID, newDependency: newLibintlDylibID) {
			return false
		} */
        
        let outputVersionCurrentPath = self.outputPath.appendingPathComponent(path: "Versions").appendingPathComponent(path: "Current")
        let versionARelativePath = "A";
        
        do {
            try fileManager.createSymbolicLink(atPath: outputVersionCurrentPath, withDestinationPath: versionARelativePath)
        } catch {
            ConsoleIO.printMessage("Failed create symlink for \(versionARelativePath) at \(outputVersionCurrentPath)", to: .error)
            
            return false
        }
        
        let outputHeadersPath = self.outputPath.appendingPathComponent(path: "Headers")
        let versionsCurrentHeadersRelativePath = "Versions/Current/Headers"
        
        do {
            try fileManager.createSymbolicLink(atPath: outputHeadersPath, withDestinationPath: versionsCurrentHeadersRelativePath)
        } catch {
            ConsoleIO.printMessage("Failed create symlink for \(versionsCurrentHeadersRelativePath) at \(outputHeadersPath)", to: .error)
            
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
    
    func processCopiedFile(copiedFilePath: String) -> Bool {
        if copiedFilePath.isDylibFile() {
            if !stripAllArchitectures(except: "x86_64", of: copiedFilePath) {
                return false
            }
        }
        
        return true
    }
    
    func compressedData(ofFileAtPath filePath: String) -> Data? {
        do {
            let data = try Data(contentsOf: filePath.fileURLFromPath())
            let compressedData = data.gzipped()
            
            return compressedData
        } catch {
            return nil
        }
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
	
	func runProcessAndGetStdOut(launchPath: String, arguments: [String]) -> (success: Bool, stdout: String) {
        let proc = Process()
        
        proc.launchPath = launchPath
        proc.arguments = arguments
		
		let pipeStdOut = Pipe()
		proc.standardOutput = pipeStdOut
        
        proc.launch()
        proc.waitUntilExit()
		
		let success = proc.terminationStatus == 0
		
		let dataStdOut = pipeStdOut.fileHandleForReading.readDataToEndOfFile()
		
		var stringStdOut = ""
		
		if let str = String(data: dataStdOut, encoding: String.Encoding.utf8) {
			stringStdOut = str
		}
		
        return (success, stringStdOut)
    }
    
	func newDylibID(for fileName: String) -> String {
        return "@rpath/Mono.framework/Versions/Current/lib/\(fileName)"
    }
	
	func idOfDylib(at filePath: String) -> String? {
		ConsoleIO.printMessage("Getting ID of Dylib \(filePath)...");
		
		let ret = runProcessAndGetStdOut(launchPath: self.otoolPath, arguments: [
			"-D",
			filePath
		])
		
		if ret.success {
			let stdout = ret.stdout
			
			let id = stdout.replacingFirstOccurrence(of: "\(filePath):\n", with: "").trimmingCharacters(in: [ "\n" ])
			
			return id
		}
		
		return nil
	}
	
    func changeIDOfDylib(at filePath: String, to newID: String) -> Bool {
        ConsoleIO.printMessage("Changing ID of Dylib \(filePath) to \(newID)...");
        
		let success = runProcess(launchPath: self.installNameToolPath, arguments: [
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
	
	func changeDependencyOfDylib(at filePath: String, oldDependency: String, newDependency: String) -> Bool {
        ConsoleIO.printMessage("Changing dependency \(oldDependency) of Dylib \(filePath) to \(newDependency)...");
        
		let success = runProcess(launchPath: self.installNameToolPath, arguments: [
            "-change",
            oldDependency,
			newDependency,
            
            filePath
        ])
        
        if !success {
            ConsoleIO.printMessage("Failed to change dependency \(oldDependency) of Dylib \(filePath) to \(newDependency)", to: .error);
            
            return false
        }
        
        return true
    }
}

class CommandLineOptions {
    let monoPath: String
    let outputPath: String
    let compress: Bool
    let blacklist: [String]
    
    static func getArgumentValue(arguments: [String], optionIndex: Int) -> String? {
        let valueIndex = optionIndex + 1
        
        if arguments.count <= valueIndex {
            return nil
        } else {
            let val = arguments[valueIndex]
            
            if val.isEmpty || val.starts(with: "--") {
                return nil
            }
            
            return val
        }
    }
    
    init?(arguments: [String]) {
        var _monoPath = ""
        var _outputPath = ""
        var _compress = false
        var _blacklist = [String]()
        
        var i = 0
        
        for arg in arguments {
            let argLower = arg.lowercased()
            
            switch argLower {
            case "--mono":
                if let val = CommandLineOptions.getArgumentValue(arguments: arguments, optionIndex: i) {
                    _monoPath = val
                }
                
                break
            case "--out":
                if let val = CommandLineOptions.getArgumentValue(arguments: arguments, optionIndex: i) {
                    _outputPath = val
                }
                
                break
            case "--compress":
                _compress = true
                
                break
            case "--blacklist":
                if let val = CommandLineOptions.getArgumentValue(arguments: arguments, optionIndex: i) {
                    _blacklist = val.components(separatedBy: ",")
                }
                
                break
            default:
                break
            }
            
            i += 1
        }
        
        if _outputPath.isEmpty {
            return nil
        }
        
        self.monoPath = _monoPath
        self.outputPath = _outputPath
        self.compress = _compress
        self.blacklist = _blacklist
    }
}

class Main {
	static let usageInstructions = "mono_embedding_tool --out ~/OutputPath [--mono /Library/Frameworks/Mono.framework] [--blacklist Accessibility.dll,System.Web.Mvc.dll] [--compress]"
	static let defaultMonoPath = "/Library/Frameworks/Mono.framework"
	
    static func run() -> Bool {
        if let options = CommandLineOptions(arguments: CommandLine.arguments) {
			let monoPath = (options.monoPath.isEmpty ? defaultMonoPath : options.monoPath)
				.expandingTildeInPath()
				.appendingPathComponent(path: "Versions")
				.appendingPathComponent(path: "Current")
			
            let outputPath = options.outputPath
				.expandingTildeInPath()
				.appendingPathComponent(path: "Mono.framework")
			
            let compress = options.compress
            let blacklist = options.blacklist
            
            ConsoleIO.printMessage("")
            ConsoleIO.printMessage("Configuration:")
            ConsoleIO.printMessage("  - Mono Path:   \(monoPath)")
            ConsoleIO.printMessage("  - Output Path: \(outputPath)")
            ConsoleIO.printMessage("  - Compress:    \(compress)")
            ConsoleIO.printMessage("  - Blacklist:   \(blacklist)")
            ConsoleIO.printMessage("")
            
            if !monoPath.directoryExists() {
                ConsoleIO.printMessage("Mono Path does not exist at \(monoPath)", to: .error)
                
                return false
            }
            
            // TODO: This check does not work if the path does not already exist
            /* if !outputPath.isWritablePath() {
                ConsoleIO.printMessage("Output Path is not writable at \(outputPath)", to: .error)
                
                return false
            } */

            let fileCollector = FileCollector(systemMonoPath: monoPath, blacklistedFilenames: blacklist)

            let relativePaths = fileCollector.pathsOfCollectedFilesRelativeToSystemMonoPath()

            let monoCopier = MonoCopier(systemMonoPath: monoPath,
                                        relativeFilePathsToCopy: relativePaths,
                                        outputPath: outputPath,
                                        compress: compress)

            let success = monoCopier.copy()

            let outputPathForDisplay = outputPath.abbreviatingWithTildeInPath()

            ConsoleIO.printMessage("")
            
            if success {
                ConsoleIO.printMessage("Successfully created embeddable Mono framework at \(outputPathForDisplay)")
                
                return true
            } else {
                ConsoleIO.printMessage("Failed to create embeddable Mono framework at \(outputPathForDisplay)", to: .error)
                
                return false
            }
        } else {
            ConsoleIO.printUsage(usageInstructions)
            
            return false
        }
    }
}

exit(Main.run() ? 0 : 1)
