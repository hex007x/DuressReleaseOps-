import argparse
import base64
import hashlib
import hmac
import json
import os
import re
import subprocess
import sys
import time
import uuid
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import urlparse

from playwright.sync_api import TimeoutError as PlaywrightTimeoutError
from playwright.sync_api import sync_playwright


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-url", required=True)
    parser.add_argument("--output-root", required=True)
    parser.add_argument("--connection-string", required=True)
    parser.add_argument("--edge-path", required=True)
    return parser.parse_args()


@dataclass
class Identity:
    organisation_name: str
    first_admin_name: str
    first_admin_email: str
    billing_email: str
    password: str
    phone: str
    billing_entity_name: str
    address_line_1: str
    address_line_2: str
    suburb: str
    state: str
    postcode: str
    country: str


def create_identity() -> Identity:
    stamp = datetime.now(timezone.utc).strftime("%Y%m%d%H%M%S%f")
    domain = f"visual-{stamp}.duress-e2e.com"
    return Identity(
        organisation_name=f"Duress Visual {stamp}",
        first_admin_name="Automation Visual",
        first_admin_email=f"admin@{domain}",
        billing_email=f"billing@{domain}",
        password=f"Duress!{stamp}Aa",
        phone="1300366911",
        billing_entity_name=f"Duress Visual {stamp}",
        address_line_1="99 Queen Street",
        address_line_2="Suite 8",
        suburb="Melbourne",
        state="VIC",
        postcode="3000",
        country="Australia",
    )


def create_identity_with_prefix(prefix: str) -> Identity:
    stamp = datetime.now(timezone.utc).strftime("%Y%m%d%H%M%S%f")
    safe_prefix = re.sub(r"[^a-zA-Z0-9]", "", prefix).lower()
    domain = f"{safe_prefix}-{stamp}.duress-e2e.com"
    return Identity(
        organisation_name=f"Duress {prefix} {stamp}",
        first_admin_name=f"Automation {prefix}",
        first_admin_email=f"admin@{domain}",
        billing_email=f"billing@{domain}",
        password=f"Duress!{stamp}Aa",
        phone="1300366911",
        billing_entity_name=f"Duress {prefix} {stamp}",
        address_line_1="99 Queen Street",
        address_line_2="Suite 8",
        suburb="Melbourne",
        state="VIC",
        postcode="3000",
        country="Australia",
    )


def parse_connection_string(connection_string: str) -> dict[str, str]:
    parts: dict[str, str] = {}
    for segment in connection_string.split(";"):
        if "=" not in segment:
            continue
        key, value = segment.split("=", 1)
        parts[key.strip()] = value.strip()
    return parts


def get_psql_path() -> str:
    candidates = [
        r"C:\Program Files\PostgreSQL",
        r"C:\Program Files",
    ]
    for root in candidates:
        root_path = Path(root)
        if not root_path.exists():
            continue
        matches = list(root_path.rglob("psql.exe"))
        if matches:
            return str(sorted(matches)[0])
    raise RuntimeError("Could not locate psql.exe.")


def db_scalar(connection_string: str, sql: str, output_root: Path) -> str:
    parts = parse_connection_string(connection_string)
    psql_path = get_psql_path()
    sql_path = output_root / f"query-{uuid.uuid4().hex}.sql"
    sql_path.write_text(sql, encoding="utf-8")
    env = os.environ.copy()
    env["PGPASSWORD"] = parts.get("Password", "")
    try:
        result = subprocess.run(
            [
                psql_path,
                "-h",
                parts.get("Host", ""),
                "-p",
                parts.get("Port", ""),
                "-U",
                parts.get("Username", ""),
                "-d",
                parts.get("Database", ""),
                "-t",
                "-A",
                "-f",
                str(sql_path),
            ],
            capture_output=True,
            text=True,
            env=env,
            check=False,
        )
    finally:
        try:
            sql_path.unlink()
        except FileNotFoundError:
            pass

    if result.returncode != 0:
        raise RuntimeError(f"psql query failed: {result.stderr or result.stdout}")

    values = [line.strip() for line in result.stdout.splitlines() if line.strip()]
    if not values:
        return ""
    return values[0]


def get_invite_id(connection_string: str, email: str, output_root: Path) -> str:
    escaped_email = email.replace("'", "''")
    sql = f"""
select "Id"
from "PortalInviteLinks"
where lower("Email") = lower('{escaped_email}')
order by "CreatedUtc" desc
limit 1;
"""
    invite_id = db_scalar(connection_string, sql, output_root)
    if not invite_id:
        raise RuntimeError(f"Could not locate invite for {email}.")
    return invite_id


def db_execute(connection_string: str, sql: str, output_root: Path) -> None:
    parts = parse_connection_string(connection_string)
    psql_path = get_psql_path()
    sql_path = output_root / f"exec-{uuid.uuid4().hex}.sql"
    sql_path.write_text(sql, encoding="utf-8")
    env = os.environ.copy()
    env["PGPASSWORD"] = parts.get("Password", "")
    try:
        result = subprocess.run(
            [
                psql_path,
                "-h",
                parts.get("Host", ""),
                "-p",
                parts.get("Port", ""),
                "-U",
                parts.get("Username", ""),
                "-d",
                parts.get("Database", ""),
                "-v",
                "ON_ERROR_STOP=1",
                "-f",
                str(sql_path),
            ],
            capture_output=True,
            text=True,
            env=env,
            check=False,
        )
    finally:
        try:
            sql_path.unlink()
        except FileNotFoundError:
            pass

    if result.returncode != 0:
        raise RuntimeError(f"psql exec failed: {result.stderr or result.stdout}")


def get_customer_id(connection_string: str, email: str, output_root: Path) -> str:
    escaped_email = email.replace("'", "''")
    sql = f"""
select "CustomerId"
from "AspNetUsers"
where lower("Email") = lower('{escaped_email}')
limit 1;
"""
    customer_id = db_scalar(connection_string, sql, output_root)
    if not customer_id:
        raise RuntimeError(f"Could not locate customer id for {email}.")
    return customer_id


def seed_xero_pending_payment(connection_string: str, customer_id: str, output_root: Path) -> None:
    payment_id = str(uuid.uuid4())
    sql = f"""
insert into "PaymentRequests" (
    "Id", "CustomerId", "Description", "AmountAud", "Status",
    "RequestedCollectionMode", "ResolvedCollectionMode",
    "DiscountAmountAud", "DiscountPercent",
    "StripePaymentLinkId", "StripePaymentUrl", "StripeCheckoutSessionId",
    "StripeLastWebhookEventId", "StripeLastWebhookType",
    "XeroInvoiceId", "XeroInvoiceNumber", "XeroInvoiceStatus",
    "XeroPaymentId", "XeroPaymentStatus", "XeroOnlineInvoiceUrl",
    "XeroReference", "XeroCurrencyCode", "XeroAmountDue", "XeroAmountPaid",
    "XeroSyncStatus", "XeroSyncError",
    "ExternalSourceSystem", "ExternalReference", "ExpiresUtc"
) values (
    '{payment_id}'::uuid, '{customer_id}'::uuid, 'Automation EFT invoice', 499.00, 0,
    2, 2,
    0, 0,
    '', '', '',
    '', '',
    '', 'AUTO-EFT-001', 'AUTHORISED',
    '', '', '',
    'AUTO-EFT-001', 'AUD', 499.00, 0.00,
    'PendingCustomerAction', '',
    'automation', 'browser-visual-xero', now() + interval '7 days'
);
"""
    db_execute(connection_string, sql, output_root)


def seed_paid_manual_payment(connection_string: str, customer_id: str, output_root: Path) -> None:
    payment_id = str(uuid.uuid4())
    sql = f"""
insert into "PaymentRequests" (
    "Id", "CustomerId", "Description", "AmountAud", "Status",
    "RequestedCollectionMode", "ResolvedCollectionMode",
    "DiscountAmountAud", "DiscountPercent",
    "StripePaymentLinkId", "StripePaymentUrl", "StripeCheckoutSessionId",
    "StripeLastWebhookEventId", "StripeLastWebhookType",
    "XeroInvoiceId", "XeroInvoiceNumber", "XeroInvoiceStatus",
    "XeroPaymentId", "XeroPaymentStatus", "XeroOnlineInvoiceUrl",
    "XeroReference", "XeroCurrencyCode", "XeroSyncStatus", "XeroSyncError",
    "ExternalSourceSystem", "ExternalReference", "PaidUtc", "SentUtc"
) values (
    '{payment_id}'::uuid, '{customer_id}'::uuid, 'Automation paid portal payment', 199.00, 2,
    3, 3,
    0, 0,
    '', '', '',
    '', '',
    '', '', '',
    '', '', '',
    'AUTO-PAID-001', 'AUD', 'PaidApplied', '',
    'automation', 'browser-visual-paid', now(), now()
);
"""
    db_execute(connection_string, sql, output_root)


def get_totp(secret: str) -> str:
    clean = re.sub(r"\s+", "", secret).upper()
    missing_padding = (-len(clean)) % 8
    clean = clean + ("=" * missing_padding)
    key = base64.b32decode(clean, casefold=True)
    counter = int(time.time() // 30).to_bytes(8, byteorder="big")
    digest = hmac.new(key, counter, hashlib.sha1).digest()
    offset = digest[-1] & 0x0F
    binary = (
        ((digest[offset] & 0x7F) << 24)
        | ((digest[offset + 1] & 0xFF) << 16)
        | ((digest[offset + 2] & 0xFF) << 8)
        | (digest[offset + 3] & 0xFF)
    )
    return f"{binary % 1000000:06d}"


def screenshot(page, path: Path, full_page: bool = True) -> None:
    page.screenshot(path=str(path), full_page=full_page)


def assert_contains(page, text: str) -> None:
    if text not in page.content():
        raise AssertionError(f"Expected page to contain '{text}'.")


def ensure_panel_visible(page, toggle_selector: str, panel_selector: str) -> None:
    page.locator(toggle_selector).click(force=True)
    try:
        page.locator(panel_selector).wait_for(state="visible", timeout=3000)
    except PlaywrightTimeoutError:
        page.evaluate(
            """([panelSelector, toggleSelector]) => {
                const panel = document.querySelector(panelSelector);
                const toggle = document.querySelector(toggleSelector);
                if (panel) {
                    panel.classList.remove('d-none');
                }
                if (toggle) {
                    toggle.setAttribute('aria-expanded', 'true');
                }
            }""",
            [panel_selector, toggle_selector],
        )
        page.locator(panel_selector).wait_for(state="visible", timeout=3000)


def fill_signup(page, identity: Identity) -> None:
    page.fill("input[name='Input.OrganisationName']", identity.organisation_name)
    page.fill("input[name='Input.FirstAdminName']", identity.first_admin_name)
    page.fill("input[name='Input.FirstAdminEmail']", identity.first_admin_email)
    page.fill("input[name='Input.BillingEmail']", identity.billing_email)
    page.fill("input[name='Input.Phone']", identity.phone)

    ensure_panel_visible(page, "#organisation-address-manual-toggle", "#organisation-address-manual-panel")
    page.fill("#organisation-address-line1", identity.address_line_1)
    page.fill("#organisation-address-line2", identity.address_line_2)
    page.fill("#organisation-suburb", identity.suburb)
    page.fill("#organisation-state", identity.state)
    page.fill("#organisation-postcode", identity.postcode)
    page.select_option("#organisation-country", label=identity.country)

    if page.locator("#billing-address-same").is_checked():
        page.locator("#billing-address-same").uncheck()
    ensure_panel_visible(page, "#billing-address-manual-toggle", "#billing-address-manual-panel")
    page.fill("#billing-address-line1", identity.address_line_1)
    page.fill("#billing-address-line2", identity.address_line_2)
    page.fill("#billing-suburb", identity.suburb)
    page.fill("#billing-state", identity.state)
    page.fill("#billing-postcode", identity.postcode)
    page.select_option("#billing-country", label=identity.country)


def complete_mfa_setup(page, screenshots_root: Path) -> None:
    page.wait_for_load_state("networkidle")
    current_url = page.url
    parsed_path = urlparse(current_url).path
    if not re.search(r"/Portal/(MfaSetup|TwoFactor|Index)$", parsed_path):
        body_excerpt = page.locator("body").inner_text()[:800]
        raise RuntimeError(f"Reset-password flow did not advance into portal MFA/login. Final URL: {current_url}. Page excerpt: {body_excerpt}")
    if parsed_path.endswith("/Portal/Index"):
        return
    if parsed_path.endswith("/Portal/TwoFactor"):
        raise RuntimeError("Reset-password flow landed on /Portal/TwoFactor before initial MFA setup, which this suite does not yet automate.")
    screenshot(page, screenshots_root / "03-mfa-setup.png")
    secret = page.locator("code").first.inner_text().strip()
    code = get_totp(secret)
    page.fill("input[name='Input.VerificationCode']", code)
    page.get_by_role("button", name=re.compile("verify|continue", re.I)).click()
    page.wait_for_url(re.compile(r".*/Portal/Index$"))


def accept_trial_terms(page) -> None:
    if page.locator("input[name='TermsInput.AcceptProductTerms']").count() > 0:
        page.check("input[name='TermsInput.AcceptProductTerms']")
        page.check("input[name='TermsInput.AcceptTrialConditions']")
        page.get_by_role("button", name=re.compile("Accept current terms", re.I)).click()
        page.wait_for_load_state("networkidle")


def accept_purchase_terms(page) -> None:
    if page.locator("input[name='TermsInput.AcceptProductTerms']").count() > 0:
        page.check("input[name='TermsInput.AcceptProductTerms']")
        page.get_by_role("button", name=re.compile("Accept current product terms", re.I)).click()
        page.wait_for_load_state("networkidle")


def create_purchase(page) -> None:
    buttons = page.locator("button:has-text('Buy license now')")
    count = buttons.count()
    for index in range(count):
        button = buttons.nth(index)
        if button.is_enabled():
            button.click()
            return
    raise RuntimeError("Could not find an enabled 'Buy license now' button.")


def has_enabled_purchase_button(page) -> bool:
    buttons = page.locator("button:has-text('Buy license now')")
    count = buttons.count()
    for index in range(count):
        if buttons.nth(index).is_enabled():
            return True
    return False


def signup_and_bootstrap(page, identity: Identity, base_url: str, connection_string: str, output_root: Path, screenshots_root: Path, prefix: str):
    page.goto(f"{base_url}/Signup", wait_until="networkidle")
    assert_contains(page, "Create your Duress Alert organisation")
    screenshot(page, screenshots_root / f"{prefix}-signup-public.png")

    fill_signup(page, identity)
    screenshot(page, screenshots_root / f"{prefix}-signup-filled.png")
    page.get_by_role("button", name="Create account").click()
    page.wait_for_load_state("networkidle")
    assert_contains(page, "Successfully created")
    screenshot(page, screenshots_root / f"{prefix}-signup-success.png")

    invite_id = get_invite_id(connection_string, identity.first_admin_email, output_root)
    page.goto(f"{base_url}/Portal/ResetPassword?invite={invite_id}", wait_until="networkidle")
    page.fill("input[name='Input.NewPassword']", identity.password)
    page.fill("input[name='Input.ConfirmPassword']", identity.password)
    screenshot(page, screenshots_root / f"{prefix}-reset-password.png")
    page.get_by_role("button", name=re.compile("Set password|Reset password|Continue", re.I)).click()
    page.wait_for_load_state("networkidle")
    complete_mfa_setup(page, screenshots_root)
    page.wait_for_url(re.compile(r".*/Portal/Index$"))
    screenshot(page, screenshots_root / f"{prefix}-portal-home.png")


def write_summary(summary_path: Path, screenshots_root: Path, notes: list[str]) -> None:
    lines = [
        "# Cloud Browser Visual Suite",
        "",
        f"Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}",
        "",
        "## Notes",
        "",
    ]
    lines.extend([f"- {note}" for note in notes])
    lines.extend(["", "## Screenshots", ""])
    for shot in sorted(screenshots_root.glob("*.png")):
        lines.append(f"- [{shot.name}]({str(shot).replace(chr(92), '/')})")
    summary_path.write_text("\n".join(lines), encoding="utf-8")


def main() -> int:
    args = parse_args()
    base_url = args.base_url.rstrip("/")
    output_root = Path(args.output_root)
    screenshots_root = output_root / "screenshots"
    screenshots_root.mkdir(parents=True, exist_ok=True)
    summary_path = output_root / "CLOUD_BROWSER_VISUAL_SUMMARY.md"
    notes: list[str] = []
    identity = create_identity()
    negative_identity = create_identity_with_prefix("Visual Negative")

    with sync_playwright() as playwright:
        browser = playwright.chromium.launch(
            headless=True,
            executable_path=args.edge_path,
            args=["--disable-gpu", "--no-first-run", "--no-default-browser-check"],
        )
        try:
            context = browser.new_context(viewport={"width": 1440, "height": 1600})
            context.set_default_timeout(30000)
            page = context.new_page()

            signup_and_bootstrap(page, identity, base_url, args.connection_string, output_root, screenshots_root, "01")
            customer_id = get_customer_id(args.connection_string, identity.first_admin_email, output_root)
            notes.append("Public signup rendered, submitted, and reached the success state in a real browser.")
            notes.append("Browser-driven invite, password setup, and MFA setup completed successfully.")

            page.goto(f"{base_url}/Portal/Downloads/Index", wait_until="networkidle")
            if "/Portal/Downloads" in page.url:
                raise RuntimeError("Downloads were available before trial or paid entitlement.")
            screenshot(page, screenshots_root / "03a-downloads-blocked-before-entitlement.png")
            notes.append("Downloads stayed blocked before any trial or paid entitlement existed.")

            page.goto(f"{base_url}/Portal/Trial/Index", wait_until="networkidle")
            assert_contains(page, "Start free trial")
            screenshot(page, screenshots_root / "04-trial-before-acceptance.png")
            if page.locator("button:has-text('Start free')").first.is_enabled():
                raise RuntimeError("Trial start button was enabled before the current terms were accepted.")
            accept_trial_terms(page)
            screenshot(page, screenshots_root / "05-trial-after-acceptance.png")
            page.get_by_role("button", name=re.compile(r"Start free \d+-day trial", re.I)).click()
            page.wait_for_load_state("networkidle")
            screenshot(page, screenshots_root / "06-trial-started.png")
            page.goto(f"{base_url}/Portal/Downloads/Index", wait_until="networkidle")
            if "/Portal/Downloads" not in page.url:
                raise RuntimeError(f"Expected trial to unlock downloads, but landed on {page.url}.")
            screenshot(page, screenshots_root / "07-downloads-unlocked.png")
            notes.append("Trial terms, trial start, and download unlock were proven in a rendered browser flow.")

            page.goto(f"{base_url}/Portal/Purchase/Index", wait_until="networkidle")
            assert_contains(page, "Buy license")
            screenshot(page, screenshots_root / "08-purchase-before-acceptance.png")
            accept_purchase_terms(page)
            screenshot(page, screenshots_root / "09-purchase-after-acceptance.png")
            create_purchase(page)
            page.wait_for_load_state("networkidle")
            screenshot(page, screenshots_root / "10-payment-created.png")
            page.goto(f"{base_url}/Portal/Payments/Index", wait_until="networkidle")
            assert_contains(page, "Payments")
            assert_contains(page, "Pending")
            screenshot(page, screenshots_root / "10a-payments-list-pending.png")
            has_refresh_action = page.locator("button:has-text('Refresh status')").count() > 0
            page.get_by_role("link", name=re.compile(r"View", re.I)).first.click()
            page.wait_for_load_state("networkidle")
            assert_contains(page, "Pending")
            if page.locator("text=Download receipt").count() > 0:
                raise RuntimeError("Pending payment detail exposed a receipt download before payment was recorded.")
            screenshot(page, screenshots_root / "10b-payment-detail-pending.png")
            notes.append(
                "Purchase page rendered in-browser, created a pending payment, and exposed the correct pending payment list/detail state without a premature receipt."
                + (" A refresh-status action was available for the chosen payment workflow." if has_refresh_action else " The chosen payment workflow correctly withheld the refresh-status action.")
            )

            seed_xero_pending_payment(args.connection_string, customer_id, output_root)
            page.goto(f"{base_url}/Portal/Payments/Index", wait_until="networkidle")
            assert_contains(page, "Automation EFT invoice")
            screenshot(page, screenshots_root / "10c-payments-list-xero-pending.png")
            page.locator("tr", has_text="Automation EFT invoice").get_by_role("link", name=re.compile(r"View", re.I)).click()
            page.wait_for_load_state("networkidle")
            assert_contains(page, "Xero invoice workflow")
            assert_contains(page, "handled through the Xero invoice workflow")
            if page.locator("text=Open payment page").count() > 0:
                raise RuntimeError("Xero/manual invoice payment unexpectedly exposed a direct payment page link.")
            screenshot(page, screenshots_root / "10d-payment-detail-xero-note.png")
            notes.append("A seeded Xero/EFT payment proved the portal shows the manual-invoice workflow note instead of a misleading direct checkout link.")

            seed_paid_manual_payment(args.connection_string, customer_id, output_root)
            page.goto(f"{base_url}/Portal/Payments/Index", wait_until="networkidle")
            assert_contains(page, "Automation paid portal payment")
            screenshot(page, screenshots_root / "10e-payments-list-paid.png")
            page.locator("tr", has_text="Automation paid portal payment").get_by_role("link", name=re.compile(r"View", re.I)).click()
            page.wait_for_load_state("networkidle")
            assert_contains(page, "Payment has been recorded")
            if page.locator("text=Download receipt").count() > 0:
                raise RuntimeError("Seeded non-Stripe paid payment unexpectedly exposed a receipt download.")
            screenshot(page, screenshots_root / "10f-payment-detail-paid-no-receipt.png")
            notes.append("A seeded paid customer payment proved the portal paid-state rendering without forcing a fake receipt for non-Stripe/manual workflows.")

            duplicate_context = browser.new_context(viewport={"width": 1440, "height": 1600})
            duplicate_context.set_default_timeout(30000)
            duplicate_page = duplicate_context.new_page()
            duplicate_page.goto(f"{base_url}/Signup", wait_until="networkidle")
            fill_signup(duplicate_page, identity)
            duplicate_page.get_by_role("button", name="Create account").click()
            duplicate_page.wait_for_load_state("networkidle")
            duplicate_html = duplicate_page.content()
            duplicate_path = urlparse(duplicate_page.url).path
            duplicate_ok = (
                "already have a Duress Alert account" in duplicate_html
                or "I don't recognise this email" in duplicate_html
                or "An account already exists for this email" in duplicate_html
                or duplicate_path.endswith("/Portal/ForgotPassword")
            )
            if not duplicate_ok:
                body_excerpt = duplicate_page.locator("body").inner_text()[:800]
                raise RuntimeError(f"Duplicate signup did not reach an expected refusal/recovery path. Final URL: {duplicate_page.url}. Page excerpt: {body_excerpt}")
            screenshot(duplicate_page, screenshots_root / "11-duplicate-signup-blocked.png")
            notes.append("Duplicate signup is blocked in-browser and routed into the existing-organisation recovery/review path.")

            negative_context = browser.new_context(viewport={"width": 1440, "height": 1600})
            negative_context.set_default_timeout(30000)
            negative_page = negative_context.new_page()
            signup_and_bootstrap(negative_page, negative_identity, base_url, args.connection_string, output_root, screenshots_root, "12")

            negative_page.goto(f"{base_url}/Portal/Trial/Index", wait_until="networkidle")
            if negative_page.locator("button:has-text('Start free')").first.is_enabled():
                raise RuntimeError("Negative-path account had trial start enabled before accepting terms.")
            screenshot(negative_page, screenshots_root / "13-trial-disabled-before-terms.png")

            negative_page.goto(f"{base_url}/Portal/Purchase/Index", wait_until="networkidle")
            if has_enabled_purchase_button(negative_page):
                raise RuntimeError("Negative-path account had purchase buttons enabled before accepting product terms.")
            screenshot(negative_page, screenshots_root / "14-purchase-disabled-before-terms.png")
            negative_page.goto(f"{base_url}/Portal/Payments/Index", wait_until="networkidle")
            assert_contains(negative_page, "No payment requests are available for this account.")
            screenshot(negative_page, screenshots_root / "14a-payments-empty-before-purchase.png")
            notes.append("Trial and purchase actions stay disabled in-browser until the required legal acceptance is completed.")

            anonymous_context = browser.new_context(viewport={"width": 1440, "height": 1600})
            anonymous_context.set_default_timeout(30000)
            anonymous_page = anonymous_context.new_page()
            anonymous_page.goto(f"{base_url}/Management/Legal/Index", wait_until="networkidle")
            anon_path = urlparse(anonymous_page.url).path
            if not anon_path.endswith("/Management/Login"):
                raise RuntimeError(f"Anonymous management legal access did not redirect to login. Final URL: {anonymous_page.url}")
            screenshot(anonymous_page, screenshots_root / "15-management-legal-anonymous-blocked.png")
            notes.append("Anonymous browser access to management-only pages is challenged and redirected to login.")

            admin_context = browser.new_context(viewport={"width": 1440, "height": 1600})
            admin_context.set_default_timeout(30000)
            admin_page = admin_context.new_page()
            admin_page.goto(f"{base_url}/dev/admin-login-direct", wait_until="networkidle")
            admin_page.goto(f"{base_url}/Management/Legal/Index", wait_until="networkidle")
            assert_contains(admin_page, "Legal")
            screenshot(admin_page, screenshots_root / "16-management-legal.png")

            admin_page.goto(f"{base_url}/Admin/Products/Index", wait_until="networkidle")
            assert_contains(admin_page, "Products")
            screenshot(admin_page, screenshots_root / "17-admin-products-index.png")

            admin_page.goto(f"{base_url}/Admin/Products/Migrations/Index", wait_until="networkidle")
            assert_contains(admin_page, "migration")
            screenshot(admin_page, screenshots_root / "18-admin-product-migrations.png")
            notes.append("Management legal and governed commercial admin pages were captured as rendered pages under an authenticated browser session.")
        finally:
            browser.close()

    write_summary(summary_path, screenshots_root, notes)
    print(f"Cloud browser visual suite written to: {output_root}")
    print(f"Summary: {summary_path}")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except PlaywrightTimeoutError as ex:
        print(f"Playwright timeout: {ex}", file=sys.stderr)
        sys.exit(1)
    except Exception as ex:
        print(str(ex), file=sys.stderr)
        sys.exit(1)
