@echo off
REM ====================================================================
REM  Argon multi-place dev launcher  (Brainrot Inc.)
REM
REM  Starts BOTH Argon sync servers at once so you never have to
REM  start/stop Argon per place. Run this once, keep the two windows
REM  open, and connect each Studio's Argon plugin to its port:
REM
REM     overworld Studio  ->  localhost : 8000
REM     sanctuary Studio  ->  localhost : 8081
REM
REM  Both project files map the SAME src/, so a code edit syncs to BOTH
REM  places. Workspace (3D) stays per-place. Places differ at runtime
REM  via game.PlaceId  (WorldConfig.currentPlaceKind()).
REM ====================================================================
title Argon multi-place launcher

echo Launching Argon for BOTH places...
start "Argon overworld 8000" cmd /k argon serve --port 8000
start "Argon sanctuary 8081" cmd /k argon serve sanctuary --port 8081

echo.
echo  Done. In each Studio: Argon plugin -- Connect
echo     overworld  --  localhost:8000
echo     sanctuary  --  localhost:8081
echo.
echo  Close the two server windows to stop syncing.
echo.
pause
