@echo off
setlocal
set _oldcd="%cd%"
cd/d %~dp0
@echo on
..\..\..\msdos ..\..\..\optasm\inst\optasm vedse;
..\..\..\msdos ..\..\..\optasm\inst\olink vedse;
@echo off
cd/d %_oldcd%
endlocal