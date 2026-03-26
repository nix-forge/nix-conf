{
  version = "2.3.20";
  src = {
    url = "https://registry.npmjs.org/@rama_nigg/open-cursor/-/open-cursor-2.3.20.tgz";
    hash = "sha512-x9HTBrr3v9G9LHaLnHEnBD/L3982Ovut9ExEpnUoK/lENY7iz5cOnIHeLYpc42+m3oGqe0UUPcQoLagY9gDkwA==";
  };

  runtimeDeps = {
    opencodePlugin = {
      version = "1.1.53";
      src = {
        url = "https://registry.npmjs.org/@opencode-ai/plugin/-/plugin-1.1.53.tgz";
        hash = "sha512-9ye7Wz2kESgt02AUDaMea4hXxj6XhWwKAG8NwFhrw09Ux54bGaMJFt1eIS8QQGIMaD+Lp11X4QdyEg96etEBJw==";
      };
    };

    opencodeSdk = {
      version = "1.1.53";
      src = {
        url = "https://registry.npmjs.org/@opencode-ai/sdk/-/sdk-1.1.53.tgz";
        hash = "sha512-RUIVnPOP1CyyU32FrOOYuE7Ge51lOBuhaFp2NSX98ncApT7ffoNetmwzqrhOiJQgZB1KrbCHLYOCK6AZfacxag==";
      };
    };

    zod = {
      version = "4.1.8";
      src = {
        url = "https://registry.npmjs.org/zod/-/zod-4.1.8.tgz";
        hash = "sha512-5R1P+WwQqmmMIEACyzSvo4JXHY5WiAFHRMg+zBZKgKS+Q1viRa0C1hmUKtHltoIFKtIdki3pRxkmpP74jnNYHQ==";
      };
    };
  };
}
