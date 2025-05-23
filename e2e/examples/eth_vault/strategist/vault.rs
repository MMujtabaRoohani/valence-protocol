use std::{error::Error, str::FromStr};

use alloy::primitives::Address;
use async_trait::async_trait;
use cosmwasm_std::{Decimal, Uint128};
use localic_utils::NEUTRON_CHAIN_DENOM;
use log::info;
use valence_chain_client_utils::{
    cosmos::base_client::BaseClient,
    evm::{base_client::EvmBaseClient, request_provider_client::RequestProviderClient},
};
use valence_e2e::utils::{
    solidity_contracts::{MockERC20, ValenceVault},
    UUSDC_DENOM,
};

use crate::strategist::astroport::AstroportOps;

use super::strategy::Strategy;

#[async_trait]
pub trait EthereumVault {
    async fn calculate_redemption_rate(&self) -> Result<Decimal, Box<dyn Error>>;
    async fn calculate_total_fee(&self) -> Result<u32, Box<dyn Error>>;
}

#[async_trait]
impl EthereumVault for Strategy {
    async fn calculate_total_fee(&self) -> Result<u32, Box<dyn Error>> {
        // 2. Find withdraw fee F_total
        //   1. query Vault fee from the Eth vault
        //   2. query the dex position for their fee
        //   3. F_total = F_vault + F_position
        let eth_rp = self.eth_client.get_request_provider().await?;
        let valence_vault = ValenceVault::new(
            Address::from_str(&self.cfg.ethereum.libraries.valence_vault)?,
            &eth_rp,
        );

        let vault_cfg = self.eth_client.query(valence_vault.config()).await?;

        let fees = vault_cfg.fees;

        info!("vault fees: {:?}", fees);

        // TODO: need to decide which fee we want to take (mid_fee, out_fee, etc).
        // let pool_addr = self.pool_addr.to_string();
        // let cl_pool_cfg: ConfigResponse = self
        //     .neutron_client
        //     .query_contract_state(&pool_addr, PoolQueryMsg::Config {})
        //     .await
        //     .unwrap();

        // hardcoding flat fee for now
        let withdraw_fee = 100u32;

        if withdraw_fee > vault_cfg.maxWithdrawFeeBps {
            log::warn!(
                "Calculated withdraw fee {withdraw_fee} exceeds max allowed {}, using max",
                vault_cfg.maxWithdrawFeeBps
            );
            return Ok(vault_cfg.maxWithdrawFeeBps);
        }

        Ok(withdraw_fee)
    }

    async fn calculate_redemption_rate(&self) -> Result<Decimal, Box<dyn Error>> {
        let eth_rp = self.eth_client.get_request_provider().await?;
        let valence_vault = ValenceVault::new(
            Address::from_str(&self.cfg.ethereum.libraries.valence_vault)?,
            &eth_rp,
        );
        let eth_usdc_erc20 = MockERC20::new(
            Address::from_str(&self.cfg.ethereum.denoms.usdc_erc20)?,
            &eth_rp,
        );

        // 1. query total shares issued from the vault
        let vault_issued_shares = self.eth_client.query(valence_vault.totalSupply()).await?._0;
        let vault_current_rate = self
            .eth_client
            .query(valence_vault.redemptionRate())
            .await?
            ._0;
        info!("current vault redemption rate: {:?}", vault_current_rate);

        // 2. query shares in position account and simulate their liquidation for USDC
        let neutron_position_acc_shares = self
            .neutron_client
            .query_balance(
                &self.cfg.neutron.accounts.position,
                &self.cfg.neutron.denoms.lp_token,
            )
            .await?;
        let (usdc_amount, ntrn_amount) = self
            .simulate_liquidation(
                &self.cfg.neutron.target_pool,
                neutron_position_acc_shares,
                &self.cfg.neutron.denoms.usdc,
                NEUTRON_CHAIN_DENOM,
            )
            .await?;

        let swap_simulation_output = self
            .simulate_swap(
                &self.cfg.neutron.target_pool,
                NEUTRON_CHAIN_DENOM,
                ntrn_amount,
                &self.cfg.neutron.denoms.usdc,
            )
            .await?;

        // 3. query pending deposits (eth deposit acc + noble inbound ica + neutron deposit acc)

        let eth_deposit_usdc = self
            .eth_client
            .query(
                eth_usdc_erc20.balanceOf(Address::from_str(&self.cfg.ethereum.accounts.deposit)?),
            )
            .await?
            ._0;

        let noble_inbound_ica_usdc = self
            .noble_client
            .query_balance(
                &self.cfg.neutron.accounts.noble_inbound_ica.remote_addr,
                UUSDC_DENOM,
            )
            .await?;
        let neutron_deposit_acc_usdc = self
            .neutron_client
            .query_balance(
                &self.cfg.neutron.accounts.deposit,
                &self.cfg.neutron.denoms.usdc,
            )
            .await?;

        //   4. R = total_shares / total_assets
        let normalized_eth_balance = Uint128::from_str(&eth_deposit_usdc.to_string())?;

        let total_assets = noble_inbound_ica_usdc
            + neutron_deposit_acc_usdc
            + normalized_eth_balance.u128()
            + usdc_amount.u128()
            + swap_simulation_output.u128();
        let normalized_shares = Uint128::from_str(&vault_issued_shares.to_string())?;

        info!("total assets: {total_assets}USDC");
        info!("total shares: {}SHARES", normalized_shares.u128());
        match Decimal::checked_from_ratio(normalized_shares, total_assets) {
            Ok(ratio) => {
                info!("redemption rate: {ratio}");
                Ok(ratio)
            }
            Err(_) => {
                // this handling can be improved, just returning default for now
                // to handle startup
                info!("zero shares; defaulting to ratio of 1.0");
                Ok(Decimal::one())
            }
        }
    }
}
