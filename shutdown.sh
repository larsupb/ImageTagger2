#!/bin/bash
# shutdown.sh — Stop backend and frontend dev servers

echo "Stopping ImageTagger servers..."

# Kill processes on the known ports
lsof -ti:8000 | xargs kill 2>/dev/null && echo "Backend (port 8000) stopped." || echo "Backend was not running."
lsof -ti:3000 | xargs kill 2>/dev/null && echo "Frontend (port 3000) stopped." || echo "Frontend was not running."

echo "Done."
