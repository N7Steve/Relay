# Account, Merchant and Security Logos

Relay can use the [Brandfetch Logo Link](https://brandfetch.com/developers/logo-api) service to provide logos for accounts, merchants and securities.
Logos are matched in the following ways:

- For accounts, the institution domain of the account (set manually or by an Enable Banking connection).
- For merchants, the website entered on the family merchant.
- For securities, the ticker symbol.

Families can upload a custom logo for an account or merchant; it takes precedence over Brandfetch and is restored to the automatic logo when removed.

> [!NOTE]
> Currently ticker symbol matching cannot specify the exchange and since US exchanges are prioritized, securities from other exchanges might not have the right logo.

## Enabling Brandfetch Integration

A Brandfetch Client ID is required and to obtain a client ID, sign up for an account [here](https://brandfetch.com/developers/logo-api).

Enter the Client ID in the Relay settings under the `Self-Hosting` section and enable external logos there.
Alternatively, you can provide the client id using the `BRAND_FETCH_CLIENT_ID` environment variable to the web and worker services.
![CLIENT_ID screenshot](logos-clientid.png)
