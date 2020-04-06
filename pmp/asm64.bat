@echo off
setlocal
set _oldcd="%cd%"
cd/d %~dp0
@echo on
..\..\..\msdos ..\..\..\optasm\inst\optasm pmp;
..\..\..\msdos ..\..\..\optasm\inst\olink pmp,pmp.com;
@echo off
cd/d %_oldcd%
endlocal