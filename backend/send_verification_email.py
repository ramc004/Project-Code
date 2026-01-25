import smtplib
from email.message import EmailMessage

def send_verification_email(recipient_email: str, code: str):
    """
    Sends a 6-digit verification code to the specified email.
    """
    sender_email = "ramcaleb50@gmail.com"
    with open("hello.txt", "r") as f:
        sender_password = f.read().strip()

    msg = EmailMessage()
    msg["From"] = sender_email
    msg["To"] = recipient_email
    msg["Subject"] = "Your Verification Code"
    msg.set_content(f"Your 6-digit verification code is: {code}")

    try:
        with smtplib.SMTP_SSL("smtp.gmail.com", 465) as server:
            server.login(sender_email, sender_password)
            server.send_message(msg)
        return True
    except Exception as e:
        print(f"Failed to send email: {e}")
        return False