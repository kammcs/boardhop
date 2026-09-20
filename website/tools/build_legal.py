#!/usr/bin/env python3
"""Generate the site's legal pages from one shared chrome.

The site is plain static HTML with no build step — that is the point, it has to
drop into an S3 bucket or a DocumentRoot untouched. But six legal documents
sharing a header, a footer and a placeholder banner is exactly the kind of
duplication that drifts, so those six are written here and emitted whole.

    python website/tools/build_legal.py

Everything else on the site (index.html, pricing.html) is hand-written and this
script does not touch it.

Every document here is a PLACEHOLDER: the structure and the factual claims about
how Boardhop works are right, the wording has not been reviewed by a lawyer.
Search for PLACEHOLDER-LEGAL before launch.
"""

import os

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(os.path.dirname(HERE), "legal")

# The one date shown on every document. Bump it when the wording changes.
EFFECTIVE = "20 September 2026"
ENTITY = "KammCS"

NAV = [
    ("../index.html#features", "Features", False),
    ("../index.html#big-screens", "Tablets", True),
    ("../pricing.html", "Pricing", False),
    ("../index.html#roadmap", "Roadmap", True),
]

LEGAL_LINKS = [
    ("privacy.html", "Privacy policy"),
    ("terms.html", "Terms of service"),
    ("refunds.html", "Refund policy"),
    ("dpa.html", "Data processing addendum"),
    ("subprocessors.html", "Subprocessors"),
    ("security.html", "Security"),
]

PLACEHOLDER_BANNER = """      <div class="placeholder-note" role="note">
        <p>
          <strong>Placeholder.</strong> This document describes how Boardhop
          actually works, but its wording has not been reviewed by a lawyer and
          it is not yet binding. It is published so the app stores, the
          Marketplace listing and prospective customers have something to read
          during the beta. The reviewed version replaces it before public
          launch.
        </p>
      </div>
"""


def nav_html():
    items = []
    for href, label, optional in NAV:
        opt = " data-optional" if optional else ""
        items.append(f'          <a href="{href}"{opt}>{label}</a>')
    items.append(
        '          <a class="btn btn-primary" href="../index.html#get">Get the beta</a>'
    )
    return "\n".join(items)


def footer_legal_html(current):
    items = []
    for href, label in LEGAL_LINKS[:5]:
        items.append(f"              <li><a href=\"{href}\">{label}</a></li>")
    return "\n".join(items)


def toc_html(sections):
    items = "\n".join(
        f'            <li><a href="#{slug}">{title}</a></li>' for slug, title in sections
    )
    return f"""      <nav class="toc" aria-label="On this page">
        <h4>On this page</h4>
        <ol>
{items}
        </ol>
      </nav>
"""


SITE = "https://boardhop.dev"
CARD = f"{SITE}/img/brand/og-card.png"
CARD_ALT = (
    "The Boardhop app on an iPhone showing an Azure DevOps board, beside the "
    "words Azure DevOps in your pocket."
)


def social_html(url, title, description):
    """Open Graph and Twitter tags, so a shared link unfurls as a card.

    Every page carries the same image. A 1200x630 PNG, not the app icon and
    not a WebP: a square image in a summary_large_image card gets letterboxed,
    and WebP is the format link previews handle worst -- Apple's iMessage is
    unreliable with it and Facebook and LinkedIn have declined it outright.
    The explicit width and height let a scraper lay the card out without
    downloading the image first.
    """
    tags = [
        ("property", "og:site_name", "Boardhop"),
        ("property", "og:locale", "en_US"),
        ("property", "og:type", "website"),
        ("property", "og:title", title),
        ("property", "og:description", description),
        ("property", "og:url", url),
        ("property", "og:image", CARD),
        ("property", "og:image:type", "image/png"),
        ("property", "og:image:width", "1200"),
        ("property", "og:image:height", "630"),
        ("property", "og:image:alt", CARD_ALT),
        ("name", "twitter:card", "summary_large_image"),
        ("name", "twitter:title", title),
        ("name", "twitter:description", description),
        ("name", "twitter:image", CARD),
    ]
    return "\n".join(
        '    <meta {k}="{key}" content="{v}" />'.format(
            k=kind, key=key, v=val.replace("&", "&amp;").replace('"', "&quot;")
        )
        for kind, key, val in tags
    )


PAGE = """<!doctype html>
<html lang="en" class="no-js">
  <head>
    <meta charset="utf-8" />
    <!-- Removed before first paint, so the reveal animations only ever apply
         where JavaScript can also undo them. See css/site.css. -->
    <script>document.documentElement.classList.remove("no-js");</script>
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>{title} — Boardhop</title>
    <meta name="description" content="{description}" />
    <link rel="canonical" href="https://boardhop.dev/legal/{slug}.html" />
    <meta name="robots" content="index, follow" />
{social}
    <meta name="theme-color" content="#0d1016" />
    <link rel="icon" href="../favicon.ico" sizes="any" />
    <link rel="apple-touch-icon" href="../img/brand/apple-touch-icon.png" />
    <link rel="preconnect" href="https://fonts.googleapis.com" />
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
    <link
      href="https://fonts.googleapis.com/css2?family=Archivo:wdth,wght@62..125,400..900&family=Inter:wght@400;500;600;700&display=swap"
      rel="stylesheet"
    />
    <link rel="stylesheet" href="../css/site.css" />
  </head>
  <body>
    <a class="skip-link" href="#main">Skip to content</a>

    <header class="nav" data-nav>
      <div class="wrap nav-inner">
        <a class="brand" href="../index.html">
          <img src="../img/brand/icon-128.webp" alt="" width="34" height="34" />
          Boardhop
        </a>
        <nav class="nav-links" aria-label="Main">
{nav}
        </nav>
      </div>
    </header>

    <main id="main" class="doc">
      <div class="wrap">
        <p class="eyebrow">{eyebrow}</p>
        <h1 style="font-size: clamp(2.1rem, 5vw, 3.1rem)">{title}</h1>
        <div class="doc-meta">
          <span>Effective {effective}</span>
          <span>Last updated {effective}</span>
          <span>{entity}, publisher of Boardhop</span>
        </div>

{banner}{toc}
        <div class="doc-body">
{body}
        </div>
      </div>
    </main>

    <footer class="footer">
      <div class="wrap">
        <div class="footer-grid">
          <div>
            <a class="brand" href="../index.html" style="margin-bottom: 12px">
              <img src="../img/brand/icon-128.webp" alt="" width="34" height="34" />
              Boardhop
            </a>
            <p style="max-width: 24rem">
              A mobile client for Azure DevOps Services. Built by {entity}.
            </p>
          </div>
          <div>
            <h4>Product</h4>
            <ul>
              <li><a href="../index.html#features">Features</a></li>
              <li><a href="../index.html#big-screens">Tablets</a></li>
              <li><a href="../pricing.html">Pricing</a></li>
              <li><a href="../index.html#roadmap">Roadmap</a></li>
              <li><a href="../index.html#faq">FAQ</a></li>
            </ul>
          </div>
          <div>
            <h4>Legal</h4>
            <ul>
{legal_links}
            </ul>
          </div>
          <div>
            <h4>Contact</h4>
            <ul>
              <li><a href="mailto:hello@boardhop.dev">hello@boardhop.dev</a></li>
              <li><a href="security.html">Security</a></li>
              <li><a href="mailto:support@boardhop.dev">Support</a></li>
            </ul>
          </div>
        </div>
        <div class="footer-bottom">
          <span>&copy; <span data-year>2026</span> {entity}. All rights reserved.</span>
          <span
            >Azure DevOps is a trademark of Microsoft Corporation. Boardhop is not
            affiliated with or endorsed by Microsoft.</span
          >
        </div>
      </div>
    </footer>

    <script src="../js/site.js" defer></script>
  </body>
</html>
"""


# --------------------------------------------------------------------- bodies

PRIVACY_SECTIONS = [
    ("who", "Who we are"),
    ("short", "The short version"),
    ("app", "What the app does with your data"),
    ("relay", "What the relay sees"),
    ("counting", "The active-user count"),
    ("diagnostics", "Diagnostics and crash data"),
    ("sharing", "Who else is involved"),
    ("retention", "How long anything is kept"),
    ("rights", "Your rights"),
    ("children", "Children"),
    ("changes", "Changes"),
    ("contact-privacy", "Contact"),
]

PRIVACY_BODY = """          <h2 id="who">1. Who we are</h2>
          <p>
            Boardhop is a mobile application for Azure DevOps Services published
            by {entity} (&ldquo;we&rdquo;, &ldquo;us&rdquo;). This policy covers
            the Boardhop mobile app, the Boardhop extension for the Azure DevOps
            Marketplace, the Boardhop relay service, and this website.
          </p>
          <p>
            Where an organization turns on the Boardhop relay for its Azure
            DevOps organization, that organization is the controller of the
            event metadata described in section 4 and we act as its processor.
            For your own account and billing details we are the controller.
          </p>

          <h2 id="short">2. The short version</h2>
          <ul>
            <li>
              <strong>Your work content never reaches us.</strong> The app talks
              to Azure DevOps directly from your device using your own
              credentials. Work items, comments, code, diffs and wiki pages go
              between your device and Microsoft, not through us.
            </li>
            <li>
              <strong>We have no accounts.</strong> There is no Boardhop login,
              no password and no profile. You sign in with your existing
              Microsoft work or school account.
            </li>
            <li>
              <strong>No advertising and no tracking.</strong> We do not sell
              data, we do not run advertising, and there are no third-party
              analytics or advertising SDKs in the app.
            </li>
            <li>
              <strong>Notifications carry a pointer, not content.</strong> A push
              says who did what to which item, and links to it. Your device then
              fetches the detail with your own credentials.
            </li>
          </ul>

          <h2 id="app">3. What the app does with your data</h2>
          <h3>Sign-in</h3>
          <p>
            You sign in through Microsoft Entra ID. We never see your password.
            The access and refresh tokens Microsoft issues are stored in the
            operating system's secure store on your device (the iOS Keychain or
            the Android Keystore) and are used only to call Azure DevOps. They
            are not transmitted to us, except for the one-off organization
            check described in section 4, where the token is used and discarded
            and never written down.
          </p>
          <h3>The offline cache</h3>
          <p>
            Pages you open are cached on your device so the app works without a
            signal. That cache lives only on your device, is namespaced per
            account, and is deleted when you sign that account out or remove the
            app.
          </p>
          <h3>Settings</h3>
          <p>
            Your preferences — theme, default project, notification choices —
            are stored on your device. Notification preferences are additionally
            stored by the relay when your organization uses it, because the
            relay needs them to decide what to send.
          </p>

          <h2 id="relay">4. What the relay sees</h2>
          <p>
            The relay only exists for organizations whose administrator has
            installed the Boardhop extension and turned it on. If your
            organization has not, nothing in this section applies to you and the
            relay holds nothing about you.
          </p>
          <h3>Device registration</h3>
          <p>
            To receive notifications your device registers with the relay. It
            presents its Apple or Google push token together with your Azure
            DevOps token. We use your token once, to confirm with Microsoft that
            you are a member of that organization and to learn your user id, and
            then discard it. <strong>We never store your Azure DevOps
            token.</strong> What we keep is the organization id, your Azure
            DevOps user id, your device's push token, and your notification
            preferences.
          </p>
          <h3>Events</h3>
          <p>
            Azure DevOps sends the relay a webhook when something happens in
            your organization — a comment, a review request, an assignment, a
            finished run, a waiting approval. The relay reads that payload in
            memory to work out who should be told and which item it concerns,
            and <strong>persists nothing from it</strong>: not the payload, not
            comment text, not descriptions, not code.
          </p>
          <h3>What is sent to Apple and Google</h3>
          <p>
            Only a pointer: the organization, the event type, the type and id of
            the item, the display name of the person who acted, a short verb
            such as &ldquo;replied on&rdquo;, a title of at most 80 characters,
            and a link. Item titles are metadata that appear in every list view
            in Azure DevOps; comment bodies, descriptions and code are content
            and are never included. Your device fetches the detail itself, with
            your own credentials, before showing you the notification.
          </p>
          <h3>Logs</h3>
          <p>
            The relay logs the pointer it emitted, the organization, and
            technical delivery results, with credentials redacted. These logs
            exist to debug delivery failures.
          </p>

          <h2 id="counting">5. The active-user count</h2>
          <p>
            Organizations on the paid plan are billed per active user. To do
            that the relay records, for each organization and each calendar
            month, the set of Azure DevOps user ids that opened the app for that
            organization. It records that a user was active, not what they did.
            Your organization's administrators can see this list — it is shown
            in the admin hub so an invoice can be checked.
          </p>

          <h2 id="diagnostics">6. Diagnostics and crash data</h2>
          <p>
            Store builds of the app contain no analytics SDK and no crash
            reporting service. Diagnostic screens exist only in internal builds
            and never leave the device. If you send us a diagnostic report
            yourself, you choose what it contains before it is sent.
          </p>
          <p>
            Apple and Google may provide us with aggregate, anonymised crash and
            install statistics from their own stores; this is governed by their
            policies and we cannot identify you from it.
          </p>

          <h2 id="sharing">7. Who else is involved</h2>
          <p>
            We use a small number of service providers. They are listed, with
            what each one receives and where it is processed, on the
            <a href="subprocessors.html">subprocessors page</a>. We do not sell
            personal data and we do not share it for advertising.
          </p>
          <p>
            We will disclose data if we are legally required to. Where the law
            allows, we will tell the affected organization first.
          </p>

          <h2 id="retention">8. How long anything is kept</h2>
          <table>
            <thead>
              <tr><th>What</th><th>Where</th><th>Kept for</th></tr>
            </thead>
            <tbody>
              <tr><td>Azure DevOps tokens</td><td>Your device only</td><td>Until you sign out</td></tr>
              <tr><td>Offline cache</td><td>Your device only</td><td>Until you sign out or remove the app</td></tr>
              <tr><td>Device registration</td><td>Relay</td><td>Until the device unregisters, the token is rejected by Apple or Google, or 90 days of inactivity</td></tr>
              <tr><td>Webhook payloads</td><td>Relay, in memory</td><td>Not persisted</td></tr>
              <tr><td>Delivery logs</td><td>Relay</td><td>30 days</td></tr>
              <tr><td>Active-user ledger</td><td>Relay</td><td>24 months, for billing history</td></tr>
              <tr><td>Billing records</td><td>Stripe and our records</td><td>As long as tax law requires</td></tr>
            </tbody>
          </table>

          <h2 id="rights">9. Your rights</h2>
          <p>
            Depending on where you live you may have the right to access,
            correct, delete or export the personal data we hold, to object to
            processing, or to complain to a supervisory authority. Because most
            of what concerns you sits in your employer's Azure DevOps
            organization rather than with us, the fastest route is usually your
            own administrator. For the little we hold — your device
            registration, your notification preferences and the fact that you
            were active in a month — write to
            <a href="mailto:privacy@boardhop.dev">privacy@boardhop.dev</a> and
            we will respond within 30 days.
          </p>
          <p>
            You can remove everything we hold about you at any time by turning
            off notifications in the app or by signing out, which unregisters
            the device.
          </p>

          <h2 id="children">10. Children</h2>
          <p>
            Boardhop is a tool for workplaces and is not directed at children. We
            do not knowingly collect data from anyone under 16.
          </p>

          <h2 id="changes">11. Changes</h2>
          <p>
            If we change this policy materially we will update the date at the
            top and, for organizations on a paid plan, notify the billing contact
            before the change takes effect.
          </p>

          <h2 id="contact-privacy">12. Contact</h2>
          <p>
            {entity}, publisher of Boardhop —
            <a href="mailto:privacy@boardhop.dev">privacy@boardhop.dev</a>.
            Postal address to be added before public launch.
          </p>
"""

TERMS_SECTIONS = [
    ("acceptance", "Acceptance"),
    ("service", "What the service is"),
    ("accounts", "Your Microsoft account"),
    ("your-org", "Your organization's data"),
    ("acceptable", "Acceptable use"),
    ("beta", "Beta software"),
    ("fees", "Fees and payment"),
    ("ip", "Intellectual property"),
    ("third-party", "Microsoft and other third parties"),
    ("availability", "Availability"),
    ("warranty", "Disclaimer"),
    ("liability", "Limitation of liability"),
    ("indemnity", "Indemnity"),
    ("termination", "Termination"),
    ("law", "Governing law"),
    ("changes-terms", "Changes to these terms"),
]

TERMS_BODY = """          <h2 id="acceptance">1. Acceptance</h2>
          <p>
            These terms are an agreement between you (and, where you are acting
            for an organization, that organization) and {entity}, the publisher
            of Boardhop. By installing the Boardhop app, installing the Boardhop
            extension, or using the Boardhop relay, you accept them. If you do
            not accept them, do not use the service.
          </p>
          <p>
            If you are accepting on behalf of an organization, you confirm that
            you have the authority to bind it.
          </p>

          <h2 id="service">2. What the service is</h2>
          <p>Boardhop consists of:</p>
          <ul>
            <li>a mobile application for iOS and Android that reads and writes your Azure DevOps Services data on your behalf;</li>
            <li>an extension for the Azure DevOps Marketplace that an administrator installs to configure notifications;</li>
            <li>the Boardhop relay, an optional paid service that turns Azure DevOps events into push notifications.</li>
          </ul>
          <p>
            The app is provided free of charge. The relay is provided under the
            plan your organization has bought, described on the
            <a href="../pricing.html">pricing page</a>.
          </p>

          <h2 id="accounts">3. Your Microsoft account</h2>
          <p>
            Boardhop uses your existing Microsoft Entra ID account. We do not
            issue credentials and we cannot grant, widen or restrict your access
            to anything in Azure DevOps — you see and change exactly what your
            Azure DevOps permissions already allow. You are responsible for
            keeping your device and your Microsoft account secure.
          </p>

          <h2 id="your-org">4. Your organization's data</h2>
          <p>
            Your data stays yours. We claim no ownership of anything in your
            Azure DevOps organization. Our handling of the limited data that
            does reach us is set out in the
            <a href="privacy.html">privacy policy</a>, and for organizations on
            a paid plan in the
            <a href="dpa.html">data processing addendum</a>.
          </p>

          <h2 id="acceptable">5. Acceptable use</h2>
          <p>You agree not to:</p>
          <ul>
            <li>use Boardhop to access an Azure DevOps organization you are not authorised to access;</li>
            <li>reverse engineer, decompile or tamper with the app, the extension or the relay, except where the law says you may;</li>
            <li>circumvent the licence enforcement, the active-user counting, or any rate limit;</li>
            <li>resell, sublicense or provide the relay as a service to a third party;</li>
            <li>use the service in a way that damages it, degrades it for other customers, or breaks any law.</li>
          </ul>
          <p>
            We may suspend access that is breaking these rules or endangering the
            service, and will tell you why.
          </p>

          <h2 id="beta">6. Beta software</h2>
          <p>
            Boardhop is currently in beta. Beta releases may contain defects,
            may change without notice, and may be withdrawn. Features described
            on this website as planned or in progress are not commitments and do
            not form part of this agreement. Do not rely on Boardhop as the only
            way your organization receives an important notification.
          </p>

          <h2 id="fees">7. Fees and payment</h2>
          <p>
            Paid plans are bought by an organization and billed per active user
            per calendar month, with a monthly minimum, as described on the
            pricing page. An active user is one who opened the app for that
            organization at least once during the month.
          </p>
          <ul>
            <li>Payments are processed by Stripe as merchant of record. Stripe's terms apply to the payment itself.</li>
            <li>Prices are exclusive of tax unless stated; applicable sales tax, VAT or GST is added at checkout.</li>
            <li>Subscriptions renew automatically until cancelled, and can be cancelled at any time for the end of the current period.</li>
            <li>If a payment fails we will give you a grace period and a warning in the admin hub before pausing push notifications. Your configuration is not deleted.</li>
            <li>Refunds are covered by the <a href="refunds.html">refund policy</a>.</li>
            <li>We may change prices with at least 30 days' notice to the billing contact, effective at your next renewal.</li>
          </ul>

          <h2 id="ip">8. Intellectual property</h2>
          <p>
            Boardhop, its name, its logo and its software are owned by {entity}
            and are licensed to you, not sold. You get a non-exclusive,
            non-transferable, revocable right to use them for as long as this
            agreement lasts. All other rights are reserved. Third-party
            open-source components are used under their own licences, listed in
            the app.
          </p>

          <h2 id="third-party">9. Microsoft and other third parties</h2>
          <p>
            Boardhop is an independent product. It is not affiliated with,
            sponsored by or endorsed by Microsoft Corporation. Azure DevOps,
            Microsoft Entra ID and related names are Microsoft's trademarks.
            Your use of Azure DevOps is governed by your agreement with
            Microsoft, and we are not responsible for Azure DevOps' availability,
            behaviour or changes to it.
          </p>

          <h2 id="availability">10. Availability</h2>
          <p>
            We aim to keep the relay running continuously but do not offer a
            service level agreement during the beta. Push notification delivery
            additionally depends on Apple and Google, whose services we do not
            control. The app itself keeps working without the relay.
          </p>

          <h2 id="warranty">11. Disclaimer</h2>
          <p>
            To the maximum extent permitted by law, the service is provided
            &ldquo;as is&rdquo; and &ldquo;as available&rdquo;, without
            warranties of any kind, express or implied, including merchantability,
            fitness for a particular purpose and non-infringement. Some
            jurisdictions do not allow this, in which case the exclusions apply
            only as far as the law permits, and your statutory consumer rights
            are unaffected.
          </p>

          <h2 id="liability">12. Limitation of liability</h2>
          <p>
            To the maximum extent permitted by law, neither party is liable for
            indirect, incidental, special or consequential damages, or for lost
            profits, revenue or data. Our total liability arising out of this
            agreement is limited to the greater of the fees you paid us in the
            twelve months before the claim, or one hundred US dollars. Nothing
            here limits liability for fraud, wilful misconduct, or anything that
            cannot be limited by law.
          </p>

          <h2 id="indemnity">13. Indemnity</h2>
          <p>
            You will indemnify us against claims arising from your use of the
            service in breach of these terms or of any law.
          </p>

          <h2 id="termination">14. Termination</h2>
          <p>
            You may stop using Boardhop at any time by removing the app, and an
            administrator may remove the extension and cancel the subscription.
            We may terminate for material breach that is not fixed within 30
            days of notice, or immediately where the breach endangers the
            service or is unlawful. On termination your right to use the service
            ends; sections 8, 11, 12, 13 and 15 survive.
          </p>

          <h2 id="law">15. Governing law</h2>
          <p>
            These terms are governed by the laws of
            <strong>[JURISDICTION &mdash; to be set before launch]</strong>,
            without regard to its conflict of laws rules, and the courts of that
            place have exclusive jurisdiction.
          </p>

          <h2 id="changes-terms">16. Changes to these terms</h2>
          <p>
            We may update these terms. Material changes are announced at least 30
            days before they take effect, by notice to the billing contact of
            paid organizations and by updating the date at the top of this page.
            Continuing to use the service after that date is acceptance.
          </p>
          <p>
            Questions:
            <a href="mailto:hello@boardhop.dev">hello@boardhop.dev</a>.
          </p>
"""

REFUNDS_SECTIONS = [
    ("scope-ref", "What this covers"),
    ("trial", "The trial comes first"),
    ("policy", "Refunds"),
    ("cancel", "Cancelling"),
    ("disputes", "Billing disputes"),
    ("annual", "Annual plans"),
    ("how", "How to ask"),
]

REFUNDS_BODY = """          <h2 id="scope-ref">1. What this covers</h2>
          <p>
            The Boardhop app is free, so nothing in it can be refunded. This
            policy covers paid subscriptions to the Boardhop relay, bought by an
            organization.
          </p>
          <p>
            Payments are taken by Stripe as merchant of record. Statutory
            consumer rights, and any rights granted by Stripe's own policies,
            are in addition to what is written here, not limited by it.
          </p>

          <h2 id="trial">2. The trial comes first</h2>
          <p>
            Every organization gets 30 days of the paid plan free, with no card
            and no automatic charge at the end. We do this so that nobody has to
            ask for a refund to find out whether Boardhop suits them. If the
            trial ends without a subscription, push notifications simply pause
            and everyone keeps the free app.
          </p>

          <h2 id="policy">3. Refunds</h2>
          <ul>
            <li>
              <strong>First paid month.</strong> If the service did not do what
              this website says it does, tell us within 30 days of the first
              charge and we will refund it in full.
            </li>
            <li>
              <strong>Billing errors.</strong> If you were charged for more
              active users than the admin hub counted, or charged after a
              cancellation, we will refund the difference in full, whenever you
              notice it.
            </li>
            <li>
              <strong>Extended outage.</strong> If the relay is unavailable for
              more than 24 consecutive hours in a billing period through our
              fault, ask and we will credit or refund that period pro rata.
            </li>
            <li>
              <strong>Otherwise</strong>, fees already paid for a period in
              progress are not refunded, because cancelling keeps the service
              running until the end of the period you paid for.
            </li>
          </ul>

          <h2 id="cancel">4. Cancelling</h2>
          <p>
            An administrator can cancel at any time from the customer portal
            linked in the admin hub. The subscription then runs to the end of the
            current period and does not renew. Your hook subscriptions and
            settings are left in place, so resubscribing later takes one click.
          </p>

          <h2 id="disputes">5. Billing disputes</h2>
          <p>
            The active-user list the bill is calculated from is visible to your
            administrators in the admin hub throughout the month. If it does not
            match your expectation, write to
            <a href="mailto:billing@boardhop.dev">billing@boardhop.dev</a> before
            raising a chargeback — we would much rather fix a counting mistake
            than argue with a card network.
          </p>

          <h2 id="annual">6. Annual plans</h2>
          <p>
            An annual plan can be refunded pro rata for the unused whole months
            within the first 60 days. After that it runs to the end of the term.
          </p>

          <h2 id="how">7. How to ask</h2>
          <p>
            Email <a href="mailto:billing@boardhop.dev">billing@boardhop.dev</a>
            from an address in your organization, with the organization name and
            the invoice number. We reply within five business days, and approved
            refunds are returned by Stripe to the original payment method,
            usually within ten business days.
          </p>
"""

DPA_SECTIONS = [
    ("parties", "Parties and scope"),
    ("roles", "Roles"),
    ("subject", "Subject matter and duration"),
    ("categories", "Data and data subjects"),
    ("instructions", "Our instructions"),
    ("confidentiality", "Confidentiality"),
    ("security-measures", "Security measures"),
    ("sub", "Subprocessors"),
    ("assistance", "Assistance to you"),
    ("breach-dpa", "Personal data breaches"),
    ("deletion", "Deletion and return"),
    ("audit", "Audits"),
    ("transfers", "International transfers"),
    ("sign", "How to put this in place"),
]

DPA_BODY = """          <h2 id="parties">1. Parties and scope</h2>
          <p>
            This addendum applies between the organization that subscribes to the
            Boardhop relay (&ldquo;Customer&rdquo;) and {entity}
            (&ldquo;Processor&rdquo;), and forms part of the
            <a href="terms.html">terms of service</a>. It applies only to
            personal data processed through the Boardhop relay. It does not
            apply to organizations that use only the free app, because in that
            case no personal data reaches us at all.
          </p>
          <p>
            Where the GDPR, the UK GDPR or a similar law applies to the
            Customer's use of the relay, this addendum is the Article 28
            agreement between the parties.
          </p>

          <h2 id="roles">2. Roles</h2>
          <p>
            The Customer is the controller of the event metadata and device
            registrations described below, and {entity} is the processor. Where
            {entity} determines its own purposes — billing records, account
            contacts, security logs — it acts as an independent controller under
            its <a href="privacy.html">privacy policy</a>.
          </p>

          <h2 id="subject">3. Subject matter and duration</h2>
          <p>
            <strong>Subject matter:</strong> the delivery of push notifications
            about events in the Customer's Azure DevOps organization to the
            devices of that organization's members.<br />
            <strong>Duration:</strong> for as long as the Customer's
            subscription or trial is in effect, plus the retention periods in
            section 11.<br />
            <strong>Nature and purpose:</strong> receiving event metadata from
            Azure DevOps, determining the audience, and transmitting a pointer
            to Apple's and Google's push services.
          </p>

          <h2 id="categories">4. Data and data subjects</h2>
          <p><strong>Data subjects:</strong> members of the Customer's Azure DevOps organization who install Boardhop.</p>
          <p><strong>Categories of personal data:</strong></p>
          <ul>
            <li>Azure DevOps user identifier and display name</li>
            <li>Device push token issued by Apple or Google</li>
            <li>Notification preferences and quiet hours</li>
            <li>Identifiers and short titles of the work items, pull requests, runs and approvals a notification points to</li>
            <li>Dates on which a user was active, for billing</li>
            <li>Billing contact name and email address</li>
          </ul>
          <p>
            <strong>Not processed:</strong> comment bodies, work item
            descriptions, source code, diffs, wiki content, attachments or Azure
            DevOps credentials. The relay reads webhook payloads in memory to
            determine the audience and persists nothing from them.
          </p>
          <p>
            <strong>Special categories:</strong> none are intentionally
            processed.
          </p>

          <h2 id="instructions">5. Our instructions</h2>
          <p>
            {entity} processes personal data only on the Customer's documented
            instructions, which are: these documents, the configuration the
            Customer's administrators set in the admin hub, and the app settings
            each user chooses. {entity} will tell the Customer if it believes an
            instruction breaks data protection law.
          </p>

          <h2 id="confidentiality">6. Confidentiality</h2>
          <p>
            Everyone with access to personal data is bound by confidentiality
            obligations, and access is limited to those who need it to run and
            support the service.
          </p>

          <h2 id="security-measures">7. Security measures</h2>
          <ul>
            <li>TLS for every connection, inbound and outbound.</li>
            <li>Per-organization shared secrets on webhook intake, verified on every request.</li>
            <li>Azure DevOps tokens are used to verify organization membership and then discarded; they are never written to storage.</li>
            <li>Push credentials for Apple and Google exist on the gateway only, with restricted file permissions, and are never copied into an image or a backup.</li>
            <li>Encrypted storage at rest on the host, with restricted administrative access over key-based SSH only.</li>
            <li>Data minimisation as the primary control: what is never stored cannot be breached.</li>
            <li>Logs redact credentials and retain for 30 days.</li>
          </ul>
          <p>
            The current measures are described further on the
            <a href="security.html">security page</a>. {entity} may change them,
            provided the level of protection is not reduced.
          </p>

          <h2 id="sub">8. Subprocessors</h2>
          <p>
            The Customer gives general authorisation for the subprocessors listed
            on the <a href="subprocessors.html">subprocessors page</a>. {entity}
            imposes equivalent obligations on each and remains liable for their
            performance. At least 30 days' notice is given before a new
            subprocessor is added, and the Customer may object on reasonable data
            protection grounds; if the objection cannot be resolved, the Customer
            may terminate the affected subscription without penalty.
          </p>

          <h2 id="assistance">9. Assistance to you</h2>
          <p>
            Taking into account the nature of the processing, {entity} assists
            the Customer with data subject requests, data protection impact
            assessments and consultations with supervisory authorities. In
            practice most requests are satisfied by the Customer's own Azure
            DevOps administration, because that is where the underlying data
            lives; for the limited data held by the relay, {entity} responds
            within 10 business days of a request from the Customer.
          </p>

          <h2 id="breach-dpa">10. Personal data breaches</h2>
          <p>
            {entity} notifies the Customer's billing and security contacts
            without undue delay and in any event within 48 hours of becoming
            aware of a personal data breach affecting the Customer's data, with
            the nature of the breach, the categories and approximate number of
            records affected, the likely consequences and the measures taken.
          </p>

          <h2 id="deletion">11. Deletion and return</h2>
          <p>
            Device registrations and notification preferences are deleted when a
            user signs out, when the push token is rejected, or after 90 days of
            inactivity. On termination all of the Customer's device
            registrations and preferences are deleted within 30 days. The
            active-user ledger is kept for 24 months as a billing record and the
            invoices for as long as tax law requires.
          </p>

          <h2 id="audit">12. Audits</h2>
          <p>
            {entity} makes available the information needed to demonstrate
            compliance with this addendum and, on reasonable notice and no more
            than once a year, allows an audit by the Customer or an independent
            auditor bound by confidentiality, at the Customer's cost, subject to
            reasonable arrangements to protect other customers' data.
          </p>

          <h2 id="transfers">13. International transfers</h2>
          <p>
            The relay runs in the European Union. Where personal data is
            transferred outside the EEA or the UK — to Apple's or Google's push
            services, or to Stripe — the transfer is made on the European
            Commission's Standard Contractual Clauses or another valid
            mechanism, and the data transferred is limited to what is described
            in section 4. An organization that requires event metadata to remain
            entirely inside its own tenancy should use the self-hosted relay.
          </p>

          <h2 id="sign">14. How to put this in place</h2>
          <p>
            Email <a href="mailto:privacy@boardhop.dev">privacy@boardhop.dev</a>
            with your organization's legal name and address. We will return a
            countersigned copy. A self-serve signature flow will replace this
            step before public launch.
          </p>
"""

SUB_SECTIONS = [
    ("current", "Current subprocessors"),
    ("not", "Who is not on this list"),
    ("notice", "Change notice"),
]

SUB_BODY = """          <p>
            A subprocessor is a company we use that may process personal data on
            behalf of a customer of the Boardhop relay. This page is the
            authoritative list referenced by the
            <a href="dpa.html">data processing addendum</a>.
          </p>

          <h2 id="current">Current subprocessors</h2>
          <table>
            <thead>
              <tr>
                <th>Provider</th>
                <th>What it does</th>
                <th>What it can see</th>
                <th>Where</th>
              </tr>
            </thead>
            <tbody>
              <tr>
                <td><strong>Hetzner Online GmbH</strong></td>
                <td>Hosts the relay and its database</td>
                <td>Device registrations, notification preferences, the active-user ledger, delivery logs</td>
                <td>Germany (EU)</td>
              </tr>
              <tr>
                <td><strong>Apple Inc.</strong><br /><span class="dim small">Apple Push Notification service</span></td>
                <td>Delivers notifications to iOS devices</td>
                <td>The notification pointer: device token, organization, event type, item id, actor name, short title, link</td>
                <td>United States</td>
              </tr>
              <tr>
                <td><strong>Google LLC</strong><br /><span class="dim small">Firebase Cloud Messaging</span></td>
                <td>Delivers notifications to Android devices</td>
                <td>The same notification pointer</td>
                <td>United States</td>
              </tr>
              <tr>
                <td><strong>Stripe, Inc.</strong></td>
                <td>Payments, as merchant of record; invoices and the customer portal</td>
                <td>Billing contact name and email, billing address, tax id, payment details, subscription and invoice records</td>
                <td>United States and Ireland</td>
              </tr>
              <tr>
                <td><strong>[EMAIL PROVIDER &mdash; to be named]</strong></td>
                <td>Sends trial reminders, billing notices and security notifications</td>
                <td>Billing and administrator email addresses and the content of those messages</td>
                <td>To be confirmed</td>
              </tr>
            </tbody>
          </table>
          <p class="small dim">
            Customers running the self-hosted relay use only Apple, Google and
            Stripe from this list; Hetzner is replaced by their own hosting and
            no event metadata leaves their tenancy.
          </p>

          <h2 id="not">Who is not on this list</h2>
          <ul>
            <li>
              <strong>Microsoft.</strong> Azure DevOps and Microsoft Entra ID are
              the customer's own services, under the customer's own agreement
              with Microsoft. We are not an intermediary for them — the app
              talks to Microsoft directly from the device.
            </li>
            <li>
              <strong>Analytics, advertising and crash reporting vendors.</strong>
              There are none. The store builds of the app contain no such SDK.
            </li>
            <li>
              <strong>Content delivery and cloud storage vendors.</strong> This
              website is static and serves no personal data.
            </li>
          </ul>

          <h2 id="notice">Change notice</h2>
          <p>
            We give at least 30 days' notice before adding a subprocessor, to the
            billing contact of every organization on a paid plan, and update the
            date at the top of this page. Objections go to
            <a href="mailto:privacy@boardhop.dev">privacy@boardhop.dev</a>.
          </p>
"""

SECURITY_SECTIONS = [
    ("design", "Security by what we do not hold"),
    ("creds", "Credentials"),
    ("infra", "Infrastructure"),
    ("app-sec", "The app"),
    ("vuln", "Reporting a vulnerability"),
    ("questionnaire", "For security questionnaires"),
    ("certs", "Certifications"),
]

SECURITY_BODY = """          <h2 id="design">1. Security by what we do not hold</h2>
          <p>
            The strongest control in Boardhop is architectural: most of your data
            never reaches us, so there is nothing of yours to lose.
          </p>
          <ul>
            <li>The app talks to Azure DevOps <strong>directly from the device</strong>, with the user's own token. Work items, comments, code, diffs and wiki content never transit our servers.</li>
            <li>The relay reads a webhook payload <strong>in memory only</strong>, to decide who should be notified, and persists nothing from it.</li>
            <li>What reaches Apple and Google is a <strong>pointer</strong>: organization, event type, item type and id, actor display name, a verb, a title of at most 80 characters, and a link. The pointer type is enforced at the gateway boundary; anything else is rejected.</li>
            <li>The device <strong>enriches the notification itself</strong>, fetching the detail with the user's own credentials, before it is displayed.</li>
          </ul>

          <h2 id="creds">2. Credentials</h2>
          <ul>
            <li>Azure DevOps tokens live in the iOS Keychain or the Android Keystore and are never transmitted to us — except once, at device registration, where a token is used to confirm organization membership and then discarded. It is never written to storage or to a log.</li>
            <li>Apple and Google push credentials exist on the push gateway only, with restricted file permissions, mounted read only, never copied into a container image or a backup.</li>
            <li>Each customer organization has its own webhook secret, verified on every inbound request.</li>
            <li>Logs redact tokens and secrets.</li>
          </ul>

          <h2 id="infra">3. Infrastructure</h2>
          <ul>
            <li>The relay runs in the European Union, behind TLS terminated by a reverse proxy with automatic certificate renewal.</li>
            <li>Administrative access is key-based SSH only. Password authentication and direct root login are disabled. The host firewall exposes only what the service needs.</li>
            <li>Tenants are isolated: every registration and every inbound event carries its organization identity, and per-organization rate limits keep one customer from affecting another.</li>
            <li>Operating system and dependency updates are applied on a regular cadence.</li>
            <li>Organizations that cannot accept event metadata leaving their tenancy can run the same relay themselves; it forwards pointers to our gateway over a revocable per-deployment key.</li>
          </ul>

          <h2 id="app-sec">4. The app</h2>
          <ul>
            <li>Sign-in uses Microsoft Entra ID through the system browser or the Microsoft Authenticator app. Boardhop never handles your password and supports your tenant's multi-factor and conditional access policies.</li>
            <li>Boardhop requests delegated Azure DevOps permissions only. It can never see or do more than the signed-in user already can.</li>
            <li>The offline cache is stored in the app's private container on the device and is namespaced per account; signing out deletes it.</li>
            <li>Store builds contain no analytics, advertising or crash reporting SDK. Diagnostic screens exist only in internal builds.</li>
            <li>Releases are signed and distributed only through the App Store and Google Play.</li>
          </ul>

          <h2 id="vuln">5. Reporting a vulnerability</h2>
          <p>
            Email <a href="mailto:security@boardhop.dev">security@boardhop.dev</a>.
            Tell us what you found and how to reproduce it. We acknowledge within
            two business days, keep you updated, and will credit you when a fix
            ships unless you would rather we did not.
          </p>
          <p>
            Please do not run automated scans against the relay, do not access
            another organization's data, and give us reasonable time to fix
            something before you publish it. We will not pursue legal action
            against research done in that spirit. There is no paid bounty
            programme today.
          </p>

          <h2 id="questionnaire">6. For security questionnaires</h2>
          <p>
            The short answer to most questions is that the data the question is
            about does not exist on our side. Section 4 of the
            <a href="dpa.html">data processing addendum</a> lists exactly what we
            process, and the <a href="subprocessors.html">subprocessors page</a>
            lists everyone who touches it. If your process needs more, write to
            <a href="mailto:security@boardhop.dev">security@boardhop.dev</a> and
            we will answer your questionnaire directly.
          </p>

          <h2 id="certs">7. Certifications</h2>
          <p>
            Boardhop does not hold a SOC 2 or ISO 27001 certification today. We
            would rather say so plainly than imply otherwise. If your procurement
            requires one, tell us — it is the kind of thing a committed customer
            moves up the list.
          </p>
"""

PAGES = [
    dict(
        slug="privacy",
        title="Privacy policy",
        eyebrow="Legal",
        description="How Boardhop handles your data: the app talks to Azure DevOps directly from your device, and notifications carry a pointer, never your content.",
        sections=PRIVACY_SECTIONS,
        body=PRIVACY_BODY,
    ),
    dict(
        slug="terms",
        title="Terms of service",
        eyebrow="Legal",
        description="The agreement between you and KammCS for the Boardhop app, extension and relay.",
        sections=TERMS_SECTIONS,
        body=TERMS_BODY,
    ),
    dict(
        slug="refunds",
        title="Refund policy",
        eyebrow="Legal",
        description="Refunds and cancellation for Boardhop relay subscriptions. The app is free; every organization gets a 30-day trial first.",
        sections=REFUNDS_SECTIONS,
        body=REFUNDS_BODY,
    ),
    dict(
        slug="dpa",
        title="Data processing addendum",
        eyebrow="Legal",
        description="The Article 28 processing terms for organizations subscribing to the Boardhop relay.",
        sections=DPA_SECTIONS,
        body=DPA_BODY,
    ),
    dict(
        slug="subprocessors",
        title="Subprocessors",
        eyebrow="Legal",
        description="Every company that may process personal data on behalf of a Boardhop relay customer, what it sees, and where.",
        sections=SUB_SECTIONS,
        body=SUB_BODY,
    ),
    dict(
        slug="security",
        title="Security",
        eyebrow="Trust",
        description="How Boardhop is built so that most of your data never reaches us, and how to report a vulnerability.",
        sections=SECURITY_SECTIONS,
        body=SECURITY_BODY,
    ),
]


def main():
    os.makedirs(OUT, exist_ok=True)
    nav = nav_html()
    for page in PAGES:
        url = f"{SITE}/legal/" + page["slug"] + ".html"
        html = PAGE.format(
            social=social_html(
                url, page["title"] + " — Boardhop", page["description"]
            ),
            slug=page["slug"],
            title=page["title"],
            eyebrow=page["eyebrow"],
            description=page["description"],
            nav=nav,
            banner=PLACEHOLDER_BANNER,
            toc=toc_html(page["sections"]),
            body=page["body"].format(entity=ENTITY),
            effective=EFFECTIVE,
            entity=ENTITY,
            legal_links=footer_legal_html(page["slug"]),
        )
        path = os.path.join(OUT, page["slug"] + ".html")
        with open(path, "w", encoding="utf-8", newline="\n") as fh:
            fh.write(html)
        print("wrote", os.path.relpath(path, os.path.dirname(HERE)))


if __name__ == "__main__":
    main()
