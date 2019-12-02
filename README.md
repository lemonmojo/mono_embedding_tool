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