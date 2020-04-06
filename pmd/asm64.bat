@echo off
setlocal
set _oldcd="%cd%"
cd/d %~dp0
@echo on
..\..\..\msdos ..\..\..\optasm\inst\optasm pmd;
..\..\..\msdos ..\..\..\optasm\inst\optasm pmdb2;
..\..\..\msdos ..\..\..\optasm\inst\optasm pmd86;
..\..\..\msdos ..\..\..\optasm\inst\optasm pmdppz;
..\..\..\msdos ..\..\..\optasm\inst\optasm pmdppze;
..\..\..\msdos ..\..\..\optasm\inst\optasm pmdva;
..\..\..\msdos ..\..\..\optasm\inst\optasm pmdva1;
..\..\..\msdos ..\..\..\optasm\inst\olink pmd,pmd.com;
..\..\..\msdos ..\..\..\optasm\inst\olink pmdb2,pmdb2.com;
..\..\..\msdos ..\..\..\optasm\inst\olink pmd86,pmd86.com;
..\..\..\msdos ..\..\..\optasm\inst\olink pmdppz,pmdppz.com;
..\..\..\msdos ..\..\..\optasm\inst\olink pmdppze,pmdppze.com;
..\..\..\msdos ..\..\..\optasm\inst\olink pmdva,pmdva.com;
..\..\..\msdos ..\..\..\optasm\inst\olink pmdva1,pmdva1.com;
@echo off
cd/d %_oldcd%
endlocal