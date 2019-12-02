# mono_embedding_tool

## Introduction

This tool allows you to build an embeddable Mono.framework for macOS. It's written as a single-file Swift program and can either be pre-compiled or run directly with `Swift /Path/To/mono_embedding_tool/main.swift`.

Here's a list of the actions being performed:

* Creates proper framework bundle structure (including Info.plist which is required for signing)
* Copies Mono dylibs
* Strips the dylibs of any non x86-64 architectures
* Changes the ID of dylibs using `install_name_tool`
* Copies managed assemblies
* Has support for passing in a blacklist to exclude certain assemblies
* Copies Mono machine.config
* Creates symlinks inside the generated bundle to make Mono's assembly/dylib loader happy

## Usage

Without compilation:
```
Swift /Path/To/mono_embedding_tool/main.swift --mono /Library/Frameworks/Mono.framework --out ~/OutputPath --blacklist Accessibility.dll,Commons.Xml.Relaxng.dll
```

With prior compilation:
```
mono_embedding_tool --mono /Library/Frameworks/Mono.framework --out ~/OutputPath --blacklist Accessibility.dll,Commons.Xml.Relaxng.dll
```

Arguments:

* `--mono`: The path to the system's installation of Mono.framework (usually `/Library/Frameworks/Mono.framework`).
* `--out`: The output path for the resulting embeddable Mono.framework (exluding the framework name, ie. `~/Output/`).
* `--blacklist`: A comma separated list of managed assemblies to exclude from the copy process. Partial matches are possible. ie. to exclude all assemblies that start with Mono. just use `Mono.`.