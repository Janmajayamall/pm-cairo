%lang starknet
%builtins pedersen range_check

from starkware.cairo.common.math import assert_not_zero, assert_le, assert_nn, assert_nn_le
from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.uint256 import (
    Uint256, uint256_add, uint256_sub, uint256_le, uint256_lt, uint256_check, uint256_mul, uint256_unsigned_div_rem
)
from starkware.cairo.common.hash import hash2
from starkware.starknet.common.syscalls import get_contract_address, get_caller_address, call_contract
from starkware.cairo.common.alloc import alloc


#
# MARKETS
#
@contract_interface
namespace MARKETS:
    func create_and_fund_market(
            market_id: felt,
            creator_address: felt,
            oracle_address: felt
        ) -> (success: felt):
    end

    func buy(
            market_id: felt,
            amount_out_0: Uint256,
            amount_out_1: Uint256,
            to_address: felt
        ) -> (success: felt):
    end

    func redeem_win(
            market_id: felt,
            to_address: felt
        ) -> (success: felt):
    end

    func sell(
            market_id: felt,
            amount_out_c: Uint256,
            to_address: felt
        ) -> (success: felt):
    end

    func transfer_from(
            sender: felt,
            recipient: felt,
            token_id: felt,
            amount: Uint256
        ) -> (success: felt):
    end

    func outcome_token_ids(
            market_id: felt
        ) -> (token_0_id: felt, token_1_id: felt):
    end
end

#
# IERC20
#
@contract_interface
namespace IERC20:
    func balance_of(account: felt) -> (balance: Uint256):
    end

    func transfer(recipient: felt, amount: Uint256) -> (success: felt):
    end

    func transfer_from(
            sender: felt,
            recipient: felt,
            amount: Uint256
        ) -> (success: felt):
    end
end

#
# Constants
#

#
# Storange Variables
#
@storage_var
func markets_address() -> (res: felt):
end

@storage_var
func c_token_address() -> (res: felt):
end

@storage_var
func owner() -> (res: felt):
end

#
# Constructor
#

@constructor
func constructor{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(
        _c_token_address: felt,
        _markets_address: felt,
        _owner: felt
    ):
    c_token_address.write(_c_token_address)
    markets_address.write(_markets_address)
    owner.write(_owner)
    return ()
end

#
# Externals
#

@external
func create_new_market{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(
        market_id: felt,
        oracle_address: felt,
        funding_amount: Uint256
    ) -> (success: felt):
    alloc_locals
    assert_not_zero(market_id)
    assert_not_zero(oracle_address)
    uint256_check(funding_amount)

    # markets & c_token addresses
    let (local _markets_address) = markets_address.read()
    let (local _c_token_address) = c_token_address.read()

    let (local caller) = get_caller_address()

    # transfer funding_amount to markets
    let (transfer_from_success) = IERC20.transfer_from(
        contract_address=_c_token_address,
        sender=caller,
        recipient=_markets_address,
        amount=funding_amount
    )
    assert_not_zero(transfer_from_success)

    # call create and fund market
    let (is_success) = MARKETS.create_and_fund_market(
        contract_address=_markets_address,
        market_id=market_id,
        creator_address=caller,
        oracle_address=oracle_address
    )
    assert_not_zero(is_success)

    return(1)
end

@external
func buy_min_tokens_for_exact_c_tokens{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(
        market_id: felt,
        amount_out_token_0_min: Uint256,
        amount_out_token_1_min: Uint256,
        fixed_token_index: felt,
        amount_in_c: Uint256
    ) -> (success: felt):
    alloc_locals
    assert_not_zero(market_id)
    uint256_check(amount_out_token_0_min)
    uint256_check(amount_out_token_1_min)
    uint256_check(amount_in_c)
    assert_nn_le(fixed_token_index, 1)

    # markets & c_token addresses
    let (local _markets_address) = markets_address.read()
    let (local _c_token_address) = c_token_address.read()

    let (local caller) = get_caller_address()

    # TODO check amount_out_token_min conditions holds

    # transfer amount_in_c to markets
    let (transfer_from_success) = IERC20.transfer_from(
        contract_address=_c_token_address,
        sender=caller,
        recipient=_markets_address,
        amount=amount_in_c
    )
    
    # buy
    let (is_success) = MARKETS.buy(
        contract_address=_markets_address,
        market_id=market_id,
        amount_out_0=amount_out_token_0_min,
        amount_out_1=amount_out_token_1_min,
        to_address=caller
    )
    assert_not_zero(is_success)

    return (1)
end

@external
func sell_exact_tokens_for_min_c_tokens{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(
        market_id: felt,
        amount_in_token_0: Uint256,
        amount_in_token_1: Uint256,
        fixed_token_index: felt,
        amount_out_c_min: Uint256
    ) -> (success: felt):
    alloc_locals
    assert_not_zero(market_id)
    uint256_check(amount_in_token_0)
    uint256_check(amount_in_token_1)
    uint256_check(amount_out_c_min)
    assert_nn_le(fixed_token_index, 1)

    # markets & c_token addresses
    let (local _markets_address) = markets_address.read()
    let (local _c_token_address) = c_token_address.read()

    let (local caller) = get_caller_address()

    # TODO check amount_out_c_min holds conditions holds

    # transfer amount_in_token_0 & amount_in_token_1 to markets
    let (local token_0_id, local token_1_id) = MARKETS.outcome_token_ids(
        contract_address=_markets_address,
        market_id=market_id
    )
    let (is_success_0) = MARKETS.transfer_from(
        contract_address=_markets_address,
        sender=caller,
        recipient=_markets_address,
        token_id=token_0_id,
        amount=amount_in_token_0
    )
    assert_not_zero(is_success_0)
    let (is_success_1) = MARKETS.transfer_from(
        contract_address=_markets_address,
        sender=caller,
        recipient=_markets_address,
        token_id=token_1_id,
        amount=amount_in_token_1
    )
    assert_not_zero(is_success_1)

    # sell
    let (is_success) = MARKETS.sell(
        contract_address=_markets_address,
        market_id=market_id,
        amount_out_c=amount_out_c_min,
        to_address=caller
    )
    assert_not_zero(is_success)

    return(1)
end 

@external
func redeem_win{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(
        market_id: felt,
        amount_in_token_0: Uint256,
        amount_in_token_1: Uint256
    ) -> (success: felt):
    alloc_locals
    assert_not_zero(market_id)
    uint256_check(amount_in_token_0)
    uint256_check(amount_in_token_1)
    
    # markets & c_token addresses
    let (local _markets_address) = markets_address.read()
    let (local _c_token_address) = c_token_address.read()

    let (local caller) = get_caller_address()

    # transfer amount_in_token_0 & amount_in_token_1 to markets
    let (local token_0_id, local token_1_id) = MARKETS.outcome_token_ids(
        contract_address=_markets_address,
        market_id=market_id
    )
    let (is_success_0) = MARKETS.transfer_from(
        contract_address=_markets_address,
        sender=caller,
        recipient=_markets_address,
        token_id=token_0_id,
        amount=amount_in_token_0
    )
    assert_not_zero(is_success_0)
    let (is_success_1) = MARKETS.transfer_from(
        contract_address=_markets_address,
        sender=caller,
        recipient=_markets_address,
        token_id=token_1_id,
        amount=amount_in_token_1
    )
    assert_not_zero(is_success_1)

    # redeen win
    let (is_success) = MARKETS.redeem_win(
        contract_address=_markets_address,
        market_id=market_id,
        to_address=caller
    )
    assert_not_zero(is_success)

    return(1)
end