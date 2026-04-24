import smtplib
from email.message import EmailMessage

def send_verification_email(recipient_email: str, code: str):
    sender_email = "ramcaleb50@gmail.com"

    # The password is read from a local file rather than hardcoded or passed as
    # an argument so it stays out of source control and isn't exposed in call stacks
    with open("hello.txt", "r") as f:
        sender_password = f.read().strip()

    msg = EmailMessage()
    msg["From"] = sender_email
    msg["To"] = recipient_email
    msg["Subject"] = "Your Verification Code"
    msg.set_content(f"Your 6-digit verification code is: {code}")

    try:
        # SMTP_SSL wraps the connection in TLS from the first byte on port 465,
        # unlike SMTP + starttls() which starts plain and upgrades mid-session
        # The with block ensures the socket closes cleanly whether send succeeds or fails
        with smtplib.SMTP_SSL("smtp.gmail.com", 465) as server:
            server.login(sender_email, sender_password)
            server.send_message(msg)
        return True
    # Catching the broad Exception and returning False rather than re-raising
    # keeps the function's contract simple, callers get a boolean result and
    # decide how to handle failure rather than needing to catch SMTP exceptions themselves.
    except Exception as e:
        print(f"Failed to send email: {e}")
        return False
