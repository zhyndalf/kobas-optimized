



kobas-annotate -h
IF %ERRORLEVEL% NEQ 0 exit /B 1
kobas-identify -h
IF %ERRORLEVEL% NEQ 0 exit /B 1
kobas-run -h
IF %ERRORLEVEL% NEQ 0 exit /B 1
exit /B 0
