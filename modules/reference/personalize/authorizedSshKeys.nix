# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  authorizedSshKeys = [
    # Add your SSH Public Keys here
    # NOTE: adding your pub ssh key here will make accessing and "nixos-rebuild switching" development mode
    # builds easy but still secure. Given that you protect your private keys. Do not share your keypairs across hosts.
    #
    # Shared authorized keys access poses a minor risk for developers in the same network (e.g. office) cross-accessing
    # each others development devices if:
    # - the ip addresses from dhcp change between the developers without the noticing AND
    # - you ignore the server fingerprint checks
    # You have been helped and you have been warned.
    "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAIA/pwHnzGNM+ZU4lANGROTRe2ZHbes7cnZn72Oeun/MCAAAABHNzaDo= brian@arcadia"
    "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAIEJ9ewKwo5FLj6zE30KnTn8+nw7aKdei9SeTwaAeRdJDAAAABHNzaDo= brian@minerva"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILu6O3swRVWAjP7J8iYGT6st7NAa+o/XaemokmtKdpGa brian@builder"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDdNDuKwAsAff4iFRfujo77W4cyAbfQHjHP57h/7tJde ville.ilvonen@unikie.com"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICKm9NtS/ZmrxQhY/pbRlX+9O1VaBEd8D9vojDtvS0Ru juliuskoskela@vega"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDJau0tg0qHhqFVarjNOJLi+ekSZNNqxal4iRD/pwM5W tervis@tervis-thinkpad"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAHVXc4s7e8j1uFsgHPBzpWvSI/hk5Zf6Btuj79D4hf3 tervis@tervis-servu"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIM3w7NzqMuF+OAiIcYWyP9+J3kwvYMKQ+QeY9J8QjAXm shamma-alblooshi@tii.ae"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIB/iv9RWMN6D9zmEU85XkaU8fAWJreWkv3znan87uqTW humaid@tahr"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINfyjcPGIRHEtXZgoF7wImA5gEY6ytIfkBeipz4lwnj6 Ganga.Ram@tii.ae"

    # For ghaf-installer automated testing:
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAolaKCuIUBQSBFGFZI1taNX+JTAr8edqUts7A6k2Kv7"
  ];
}
