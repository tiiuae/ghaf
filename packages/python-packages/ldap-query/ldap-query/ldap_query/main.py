# Copyright 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
import argparse
import sys

from ldap3 import ALL, GSSAPI, SASL, Connection, Server


def main():
    """
    Connects to AD, queries for users, and prints their details.
    """
    # Set up argument parser to read inputs from the command line
    parser = argparse.ArgumentParser(
        description="Query Active Directory for users using GSSAPI.",
        formatter_class=argparse.RawTextHelpFormatter,  # For better help text formatting
    )
    parser.add_argument(
        "--server", required=True, help="Hostname of the Active Directory server."
    )
    parser.add_argument(
        "--base-dn",
        required=True,
        help="Base DN for the LDAP search (e.g., 'dc=ad,dc=example,dc=com').",
    )
    parser.add_argument(
        "--min-uid", default="1", help="Minimum UID for the search range (default: 1)."
    )
    parser.add_argument(
        "--max-uid",
        default="999999",
        help="Maximum UID for the search range (default: 999999).",
    )
    args = parser.parse_args()

    # Define the LDAP filter and the attributes to retrieve using the parsed arguments
    ldap_filter = (
        f"(&(objectClass=user)(uidNumber>={args.min_uid})(uidNumber<={args.max_uid}))"
    )
    attributes_to_fetch = ["sAMAccountName", "displayName", "uidNumber", "gidNumber"]

    # Define the server and create a connection object using SASL with GSSAPI for Kerberos authentication
    server = Server(args.server, get_info=ALL)
    conn = Connection(
        server,
        authentication=SASL,
        sasl_mechanism=GSSAPI,
        auto_bind=True,
        read_only=True,
    )

    # Search the LDAP directory and print matches to stdout
    try:
        search_successful = conn.search(
            search_base=args.base_dn,
            search_filter=ldap_filter,
            attributes=attributes_to_fetch,
        )

        if not search_successful:
            print(f"Error: LDAP search failed. {conn.result}", file=sys.stderr)
            sys.exit(1)

        # Process and print the results.
        if not conn.entries:
            print(
                f"Info: No users found in the UID range {args.min_uid}-{args.max_uid}.",
                file=sys.stderr,
            )
            return

        for entry in conn.entries:
            user_data = [
                entry.sAMAccountName.value if "sAMAccountName" in entry else "N/A",
                entry.displayName.value if "displayName" in entry else "N/A",
                entry.uidNumber.value if "uidNumber" in entry else "N/A",
                entry.gidNumber.value if "gidNumber" in entry else "N/A",
            ]
            print("|".join(map(str, user_data)))

    except Exception as e:
        print(f"An error occurred: {e}", file=sys.stderr)
        sys.exit(1)

    finally:
        conn.unbind()
