import React from "react";
import { useNavigate } from "react-router-dom";
import "../index.css";

export default function WelcomeView() {
  const navigate = useNavigate();

  return (
    <div className="welcome-gradient">
      {/* VStack(spacing: 40) */}
      <div className="flex flex-col" style={{ gap: '2.5rem' }}>
        {/* Title with padding top */}
        <h1 className="text-4xl md:text-5xl font-bold text-center text-gray-800">
          AI-Based Smart Bulb
        </h1>

        {/* VStack(spacing: 22) for buttons with horizontal padding */}
        <div className="flex flex-col items-center px-12" style={{ gap: '3rem' }}>
          <button
            className="modern-button modern-button-blue"
            onClick={() => navigate("/register")}
          >
            Register
          </button>

          <button
            className="modern-button modern-button-purple"
            onClick={() => navigate("/login")}
          >
            Login
          </button>
        </div>
      </div>

      {/* Spacer - pushes content to top */}
      <div className="flex-grow"></div>
    </div>
  );
}