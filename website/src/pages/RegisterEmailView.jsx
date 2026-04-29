import { useState, useEffect } from "react";

export default function RegisterEmailView() {
  const [email, setEmail] = useState("");
  const [usernameValid, setUsernameValid] = useState(false);
  const [atSignValid, setAtSignValid] = useState(false);
  const [domainValid, setDomainValid] = useState(false);
  const [emailAvailable, setEmailAvailable] = useState(false);
  const [sendingCode, setSendingCode] = useState(false);
  const [checkingEmail, setCheckingEmail] = useState(false);
  const [errorMessage, setErrorMessage] = useState("");
  const [serverOnline, setServerOnline] = useState(true);
  const [verificationCode, setVerificationCode] = useState("");

  // Check server health on mount
  useEffect(() => {
    checkServerStatus();
  }, []);

  function validateEmail(value) {
    const parts = value.split("@");
    setUsernameValid(parts[0]?.length > 0);
    setAtSignValid(value.includes("@"));
    setDomainValid(parts.length === 2 && parts[1].includes("."));
    setEmailAvailable(false);
    setErrorMessage("");

    if (parts[0]?.length > 0 && value.includes("@") && parts.length === 2 && serverOnline) {
      checkEmailAvailability(value);
    }
  }

  async function checkServerStatus() {
    try {
      const res = await fetch("http://localhost:5000/");
      setServerOnline(res.ok);
    } catch {
      setServerOnline(false);
    }
  }

  async function checkEmailAvailability(value) {
    setCheckingEmail(true);
    setErrorMessage("");
    try {
      const res = await fetch("http://localhost:5000/check_email", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ email: value }),
      });
      const data = await res.json();
      setEmailAvailable(data.available);
      if (!data.available) setErrorMessage("This email is already registered.");
    } catch {
      setServerOnline(false);
      setErrorMessage("Server connection lost.");
    } finally {
      setCheckingEmail(false);
    }
  }

  async function sendVerificationCode() {
    if (!(usernameValid && atSignValid && domainValid && emailAvailable && serverOnline)) return;

    setSendingCode(true);
    const code = String(Math.floor(100000 + Math.random() * 900000)); // 6-digit code
    setVerificationCode(code);

    try {
      const res = await fetch("http://localhost:5000/send_code", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ email, code }),
      });
      const data = await res.json();
      if (data.status !== "success") setErrorMessage(data.message || "Failed to send code");
    } catch {
      setServerOnline(false);
      setErrorMessage("Server connection lost.");
    } finally {
      setSendingCode(false);
    }
  }

  return (
    <div className="max-w-md mx-auto p-6">
      <h1 className="text-2xl font-bold mb-4">Register Account</h1>

      {!serverOnline && (
        <div className="bg-red-100 p-4 rounded mb-4 flex justify-between items-center">
          <div>
            <p className="font-bold text-red-600">Server Offline</p>
            <p className="text-gray-600 text-sm">Please start the Flask server</p>
          </div>
          <button className="bg-blue-500 text-white px-3 py-1 rounded" onClick={checkServerStatus}>Retry</button>
        </div>
      )}

      <div className="mb-4">
        <label className="block font-semibold">Email Address</label>
        <input
          type="email"
          value={email}
          onChange={(e) => { setEmail(e.target.value); validateEmail(e.target.value); }}
          className="w-full border rounded px-3 py-2 mt-1"
          disabled={!serverOnline}
        />
      </div>

      <div className="mb-4 text-gray-600">
        <p>{usernameValid ? "✅ Username before @ is valid" : "❌ Enter username before @"}</p>
        <p>{atSignValid ? "✅ Contains @" : "❌ Missing @"}</p>
        <p>{domainValid ? "✅ Domain is valid" : "❌ Invalid domain"}</p>
        {checkingEmail && <p>⏳ Checking availability...</p>}
        {!checkingEmail && email && <p>{emailAvailable ? "✅ Email available" : "❌ Email already registered"}</p>}
      </div>

      {errorMessage && (
        <div className="bg-red-100 text-red-700 p-2 rounded mb-4">{errorMessage}</div>
      )}

      <button
        onClick={sendVerificationCode}
        disabled={!(usernameValid && atSignValid && domainValid && emailAvailable && serverOnline) || sendingCode}
        className={`w-full py-2 rounded text-white font-bold ${sendingCode ? "bg-gray-400" : "bg-green-500"}`}
      >
        {sendingCode ? "Sending..." : "Verify Email"}
      </button>
    </div>
  );
}