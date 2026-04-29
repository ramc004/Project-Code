import React from 'react'
import ReactDOM from 'react-dom/client'
import { BrowserRouter, Routes, Route } from 'react-router-dom'
import WelcomeView from "./pages/WelcomeView";
import RegisterEmailView from "./pages/RegisterEmailView";
import './index.css'

ReactDOM.createRoot(document.getElementById('root')).render(
  <React.StrictMode>
    <BrowserRouter>
      <Routes>
        <Route path="/" element={<WelcomeView />} />
        <Route path="/register" element={<RegisterEmailView />} />
      </Routes>
    </BrowserRouter>
  </React.StrictMode>
)