# AI陪伴 Legal Static Site

This folder contains the static legal/support website for App Store and Google Play submission.

## Pages

- `index.html`
- `privacy.html`
- `terms.html`
- `support.html`

## Deployment

Deploy the entire `store_legal_site/` folder to any public HTTPS static host, such as GitHub Pages, Vercel, Netlify, Firebase Hosting, or a school-managed static web server.

### GitHub Pages

This repo includes `.github/workflows/legal-site-pages.yml`, which deploys `store_legal_site/` with GitHub Actions.

Repository owner setup:

1. Merge the workflow and `store_legal_site/` into `main`.
2. Open GitHub repository Settings → Pages.
3. Set Source to **GitHub Actions**.
4. Run the workflow named **Deploy legal site to GitHub Pages**, or push to `main`.

Expected GitHub Pages URLs for this repository:

- `https://ou931023.github.io/pet_companion_app/privacy.html`
- `https://ou931023.github.io/pet_companion_app/terms.html`
- `https://ou931023.github.io/pet_companion_app/support.html`

Expected public URLs:

- `https://<your-domain>/privacy.html`
- `https://<your-domain>/terms.html`
- `https://<your-domain>/support.html`

Then build the app with:

```bash
--dart-define=PRIVACY_POLICY_URL=https://<your-domain>/privacy.html
--dart-define=TERMS_OF_SERVICE_URL=https://<your-domain>/terms.html
--dart-define=SUPPORT_URL=https://<your-domain>/support.html
--dart-define=CONTACT_EMAIL=aicompanion.support@gmail.com
```

## Store Submission Notes

- Official support email: `aicompanion.support@gmail.com`
- App Store Connect / Google Play Console support email should match this value.
- Production app builds should use `--dart-define=CONTACT_EMAIL=aicompanion.support@gmail.com`.
