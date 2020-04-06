@echo off
rem -- init
del _build_data\_final\*.*
setlocal
rem -- asm/link
title mc (1/5)
call mc\asm64.bat

title pmd (2/5)
call pmd\asm64.bat

title pmdl (3/5)
call pmdibm\asm64.bat

title pmp (4/5)
call pmp\asm64.bat

title vedse (5/5)
call vedse\asm64.bat
rem --- packaging
title _final (0/5)
mkdir _build_data\_final
copy _build_data\*.png _build_data\_final

title mc (1/5)
mkdir _build_data\_final\mc
copy mc\*.obj _build_data\_final\mc
copy mc\*.exe _build_data\_final\mc
copy mc\*.com _build_data\_final\mc

title pmd (2/5)
mkdir _build_data\_final\pmd
copy pmd\*.obj _build_data\_final\pmd
copy pmd\*.exe _build_data\_final\pmd
copy pmd\*.com _build_data\_final\pmd

title pmdl (3/5)
mkdir _build_data\_final\pmdl
copy pmdibm\*.obj _build_data\_final\pmdl
copy pmdibm\*.exe _build_data\_final\pmdl
copy pmdibm\*.com _build_data\_final\pmdl

title pmp (4/5)
mkdir _build_data\_final\pmp
copy pmp\*.obj _build_data\_final\pmp
copy pmp\*.exe _build_data\_final\pmp
copy pmp\*.com _build_data\_final\pmp

title vedse (5/5)
mkdir _build_data\_final\vedse
copy vedse\*.obj _build_data\_final\vedse
copy vedse\*.exe _build_data\_final\vedse
copy vedse\*.com _build_data\_final\vedse
rem -- end
title end
echo Build ended. Please check the log.
endlocal
pause