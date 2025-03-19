# Zig, Windows and Vulcan
This project creates a Windows Window and uses Vulkan Graphics API to draw 100 Dog images without any othere libraries.
So it will only work on Windows (i used windows 10) and vulkan sdk needs to be installed. I used zig version 0.14

# Building
Execute: 
`zig build`
in terminal to build.

But there will be some error.
 - need to fix some build pathes as there will not match your system
    - in the file build.zig change `const vulkan_sdk = "C:/Zeugs/VulkanSDK/1.4.304.1/";` to your vulkan sdk folder
    - there is also an import for the vulkan headers, but i did not figure out how to use it with the windows specific vulkan functions
 - the imported zigimg library did not work with my zig 0.14 version. I manually fixed the errors of it, so it could build. They were not that difficult.
    - if enough time has passed it will probably enough to update the zigimg library import to the newest version, if it will support zig 0.14.
    

# building shaders
Execute `shaderCompile.bat` to generate shaders.

Only required if you change the shader code. Also pathes in the bat file need to be fixed to match your system.

# Run
Execute `zig build run`