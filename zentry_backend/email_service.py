
import os
import smtplib
from email.message import EmailMessage

from dotenv import load_dotenv

load_dotenv()


def send_email(
    recipient: str,
    subject: str,
    body: str,
) -> None:
    smtp_host = os.getenv("SMTP_HOST", "smtp.gmail.com")
    smtp_port = int(os.getenv("SMTP_PORT", "587"))
    sender = os.getenv("SMTP_EMAIL", "").strip()
    app_password = os.getenv("SMTP_APP_PASSWORD", "").replace(" ", "")

    if not sender or not app_password:
        raise RuntimeError(
            "SMTP_EMAIL and SMTP_APP_PASSWORD must be configured in .env"
        )

    message = EmailMessage()
    message["From"] = sender
    message["To"] = recipient
    message["Subject"] = subject
    message.set_content(body)

    try:
        with smtplib.SMTP(smtp_host, smtp_port, timeout=20) as server:
            server.ehlo()
            server.starttls()
            server.ehlo()
            server.login(sender, app_password)
            server.send_message(message)
    except (smtplib.SMTPException, OSError) as exc:
        raise RuntimeError(
            "Email delivery failed. Check Gmail SMTP settings and App Password."
        ) from exc
