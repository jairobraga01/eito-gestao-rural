@echo off
chcp 65001 >nul
title Eito Gestão Rural - Publicar
cd /d "%~dp0"

echo.
echo ==============================================
echo   EITO GESTÃO RURAL - publicar o app na web
echo ==============================================
echo.

where flutter >nul 2>nul
if errorlevel 1 (
  echo [FALTA] O Flutter não está instalado neste computador.
  echo Instale por https://docs.flutter.dev/get-started/install/windows/web
  echo e rode este arquivo de novo.
  start "" "https://docs.flutter.dev/get-started/install/windows/web"
  pause
  exit /b 1
)

where npm >nul 2>nul
if errorlevel 1 (
  echo [FALTA] O Node.js não está instalado neste computador.
  echo Instale a versão LTS por https://nodejs.org e rode este arquivo de novo.
  start "" "https://nodejs.org"
  pause
  exit /b 1
)

where firebase >nul 2>nul
if errorlevel 1 (
  echo Instalando a ferramenta do Firebase...
  call npm install -g firebase-tools || goto erro
)

if not exist ".metadata" (
  echo Completando o projeto Flutter...
  call flutter create . --platforms=web --project-name eito_gestao_rural || goto erro
)

echo Baixando os pacotes...
call flutter pub get || goto erro

echo.
echo Compilando o app (pode levar alguns minutos)...
call flutter build web --release --no-web-resources-cdn || goto erro

echo.
echo Entrando na conta do Firebase (vai abrir o navegador na primeira vez)...
call firebase login || goto erro

echo.
echo Publicando...
call firebase deploy --only hosting,firestore:rules --project caderneta-rebanho || goto erro

echo.
echo ==============================================
echo   PRONTO! O app está no ar em:
echo   https://caderneta-rebanho.web.app
echo ==============================================
start "" "https://caderneta-rebanho.web.app"
pause
exit /b 0

:erro
echo.
echo [ERRO] Algo deu errado acima. Tire um print desta janela e mande para o Claude.
pause
exit /b 1
