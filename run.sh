#!/bin/bash
# run.sh — Start both backend and frontend dev servers

echo "Starting ImageTagger..."

# Backend
cd backend
source .venv/bin/activate
PYTHONUNBUFFERED=1 uvicorn app.main:app --reload --port 8000 2>&1 | cat &
BACKEND_PID=$!

# Frontend
cd ../frontend
npm run dev &
FRONTEND_PID=$!

echo "Backend: http://localhost:8000"
echo "Frontend: http://localhost:3000"
echo ""
echo "Press Ctrl+C to stop both servers."

trap "kill $BACKEND_PID $FRONTEND_PID 2>/dev/null" EXIT
wait
