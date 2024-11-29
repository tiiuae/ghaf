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
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGOifxDCESZZouWLpoCWGXEYOVbMz53vrXTi9RQe4Bu5 hazaa@nixos"
    "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCyh0yyYmU0dQxqs/rfpw2PMM8k9ntVux7YJi7HyxEWdMcUrYOzKN80EGCX+zE569sCF4rrOaqZdJUiuL8BnbDTWN9xjvYX4ZoEnfBi76xiFqbisyQ7OyzDPpLN2D0bunQKRK1XP238nG4gZzS9SFgGUYMiU6Huxio0O8FRQrvkoimVxQG0SYCb4h6DlR4Z+txhLskIY6vdXiFxnNCX+yxLyI+keWkQhyFubEAt9qqbwT83kvsb070VnDwHjat3PHr9QS1qL/P8s48hZtLJUtbdIIQl9/rHownKcT0V1G9AkDNUpzdYzzm4cGeC6njn7z5xl/3GNzT5lSNbbKR3zZf6Ylv56mOSjWI7RALt3vvHVZj/1ke+e6HZH00DnahOBlmoexMT7B/ZixxxfggRCwild4mcyQlTdt9wNSczI71NkYINKYJSXr0EHQASQSOVAsJVDTtXTyBN+duRFL1JoHz++UJqED2vrYl5QPhvRzf01CNy+ieTn4O+IU1BTG3veRM= hazza3@Hazzas-MBP.lan"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICwsW+YJw6ukhoWPEBLN93EFiGhN7H2VJn5yZcKId56W mb@mmm"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKbBp2dH2X3dcU1zh+xW3ZsdYROKpJd3n13ssOP092qE joerg@turingmachine"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIstCgKDX1vVWI8MgdVwsEMhju6DQJubi3V0ziLcU/2h vunny.sodhi@unikie.com"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINfyjcPGIRHEtXZgoF7wImA5gEY6ytIfkBeipz4lwnj6 Ganga.Ram@tii.ae"

    # For ghaf-installer automated testing:
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAolaKCuIUBQSBFGFZI1taNX+JTAr8edqUts7A6k2Kv7"
  ];
}
