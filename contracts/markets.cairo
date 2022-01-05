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
# IERC20
#
@contract_interface
namespace IERC20:
    func balance_of(account: felt) -> (balance: Uint256):
    end

    func transfer(recipient: felt, amount: Uint256) -> (success: felt):
    end
end

#
# Constants
#

const WETH_ADDRESS = 0

#
# Structs
#

struct OutcomeReserves:
    member reserve_0: Uint256
    member reserve_1: Uint256
end

struct Market:
    member creator_address: felt
    member oracle_address: felt
    member state: felt
    member outcome: felt
end

#
# Storage Variables
#

@storage_var
func outcome_reserves(market_id: felt) -> (res: OutcomeReserves):
end

@storage_var
func markets(market_id: felt) -> (res: Market):
end

@storage_var
func c_reserve() -> (res: Uint256):
end

@storage_var
func balances(token_id: felt, account: felt) -> (res: Uint256):
end

@storage_var
func operator_approvals(owner: felt, operator: felt) -> (res: felt):
end

# 
# Getters
#

@view
func balance_of{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(token_id: felt, account: felt) -> (balance: Uint256):
    let (_balance: Uint256) = balances.read(token_id=token_id, account=account)
    return (_balance)
end

@view 
func is_approval_for_all{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(owner: felt, operator: felt) -> (is_approved: felt):
    let (_is_approved) = operator_approvals.read(owner=owner, operator=operator)
    return (_is_approved)
end

@view 
func outcome_token_ids{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(
        market_id: felt
    ) -> (token_0_id: felt, token_1_id: felt):
    let (id_0, id_1) = _outcomeTokenIds(market_id)
    return (id_0, id_1)
end

@view 
func get_outcome_reserves{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(
        market_id: felt
    ) -> (reserve_0: Uint256, reserve_1: Uint256):
    let (o_reserves) = outcome_reserves.read(market_id=market_id)
    return (o_reserves.reserve_0, o_reserves.reserve_1)
end

#
# Externals
#

@external
func create_and_fund_market{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(
        market_id: felt,
        creator_address: felt,
        oracle_address: felt
    ) -> (success: felt):
    alloc_locals
    assert_not_zero(market_id)
    assert_not_zero(creator_address)
    assert_not_zero(oracle_address)

    # check market with market_id does not pre-exists
    let (local market) = markets.read(market_id=market_id)
    assert (market.creator_address) = 0

    # check amountIn
    let (local contract_address) = get_contract_address()
    let (c_r: Uint256) = c_reserve.read()
    let (c_balance: Uint256) = IERC20.balance_of(
        contract_address=WETH_ADDRESS,
        account=contract_address
    )
    let (amount_in: Uint256) = uint256_sub(c_balance, c_r)
    
    # update c reserve
    let (updated_c_r: Uint256, _) = uint256_add(amount_in, c_r)
    c_reserve.write(updated_c_r)

    # mint outcome tokens equivalent to amount_in
    let (local token_0_id, local token_1_id) = _outcomeTokenIds(market_id)
    let (contract_address) = get_contract_address()
    _mint(contract_address, token_0_id, amount_in)
    _mint(contract_address, token_1_id, amount_in)

    # update market outcome reserves
    local o_reserves: OutcomeReserves
    assert o_reserves.reserve_0 = amount_in
    assert o_reserves.reserve_1 = amount_in
    outcome_reserves.write(market_id, o_reserves)

    # create the market
    local new_market: Market
    assert new_market.creator_address = creator_address
    assert new_market.oracle_address = oracle_address
    assert new_market.state = 1
    assert new_market.outcome = 2
    markets.write(market_id, new_market)

    return(1)
end

@external
func buy{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(
        market_id: felt,
        amount_out_0: Uint256,
        amount_out_1: Uint256,
        to_address: felt
    ) -> (success: felt):
    alloc_locals
    assert_not_zero(market_id)
    assert_not_zero(to_address)
    uint256_check(amount_out_0)
    uint256_check(amount_out_1)

    # check market exists & is active (i.e. state = 1)
    let (local market) = markets.read(market_id=market_id)
    assert (market.state) = 1

    # check amountIn
    let (local contract_address) = get_contract_address()
    let (c_r: Uint256) = c_reserve.read()
    let (c_balance: Uint256) = IERC20.balance_of(
        contract_address=WETH_ADDRESS,
        account=contract_address
    )
    let (amount_in: Uint256) = uint256_sub(c_balance, c_r)
    
    # update c reserve
    let (updated_c_r: Uint256, _) = uint256_add(amount_in, c_r)
    c_reserve.write(updated_c_r)

    # mint outcome tokens equivalent to amount_in
    let (local token_0_id, local token_1_id) = _outcomeTokenIds(market_id)
    _mint(contract_address, token_0_id, amount_in)
    _mint(contract_address, token_1_id, amount_in)

    # transfer necessary outcome tokens to to_address
    _transfer(contract_address, to_address, token_0_id, amount_out_0)
    _transfer(contract_address, to_address, token_1_id, amount_out_1)

    # check invariance
    let (local o_reserves) = outcome_reserves.read(market_id=market_id)
    let (temp_add_0: Uint256, _) = uint256_add(o_reserves.reserve_0, amount_in) 
    let (local new_reserve_0: Uint256) = uint256_sub(temp_add_0, amount_out_0)
    let (temp_add_1: Uint256, _) = uint256_add(o_reserves.reserve_1, amount_in) 
    let (local new_reserve_1: Uint256) = uint256_sub(temp_add_1, amount_out_1)
    let (local old_rp: Uint256, _) = uint256_mul(o_reserves.reserve_0, o_reserves.reserve_1)
    let (local new_rp: Uint256, _) = uint256_mul(new_reserve_0, new_reserve_1)
    let (valid) = uint256_le(old_rp, new_rp)
    assert_not_zero(valid)

    # update outcome reserves
    local o_reserves: OutcomeReserves
    assert o_reserves.reserve_0 = new_reserve_0
    assert o_reserves.reserve_1 = new_reserve_1
    outcome_reserves.write(market_id, o_reserves)

    return(1)
end

@external
func sell{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(
        market_id: felt,
        amount_out_c: Uint256,
        to_address: felt
    ) -> (success: felt):
    alloc_locals
    assert_not_zero(market_id)
    assert_not_zero(to_address)
    uint256_check(amount_out_c)

    # check market exists & is active (i.e. state = 1)
    let (local market) = markets.read(market_id=market_id)
    assert (market.state) = 1

    # transfer amount_out_c to to_address
    let (transfer_success) = IERC20.transfer(
        contract_address=WETH_ADDRESS,
        recipient=to_address,
        amount=amount_out_c
    )
    assert_not_zero(transfer_success)

    # update c_reserve
    let (c_r: Uint256) = c_reserve.read()
    let (updated_c_r: Uint256) = uint256_sub(c_r, amount_out_c)
    c_reserve.write(updated_c_r)
    
    # check amount_in_0 & amount_in_1
    let (local token_0_id, local token_1_id) = _outcomeTokenIds(market_id)
    let (local contract_address) = get_contract_address()
    let (local o_reserves) = outcome_reserves.read(market_id=market_id)
    let (local balance_0: Uint256) = balances.read(token_id=token_0_id, account=contract_address)
    let (local balance_1: Uint256) = balances.read(token_id=token_1_id, account=contract_address)
    let (local amount_in_0: Uint256) = uint256_sub(balance_0, o_reserves.reserve_0)
    let (local amount_in_1: Uint256) = uint256_sub(balance_1, o_reserves.reserve_1)

    # burn outcome tokens equivalent to amount_out_c
    _burn(contract_address, token_0_id, amount_out_c)
    _burn(contract_address, token_0_id, amount_out_c)

    # check invariance
    let (temp_add_0: Uint256, _) = uint256_add(o_reserves.reserve_0, amount_in_0)
    let (local new_reserve_0: Uint256) = uint256_sub(temp_add_0, amount_out_c)
    let (temp_add_1: Uint256, _) = uint256_add(o_reserves.reserve_1, amount_in_1)
    let (local new_reserve_1: Uint256) = uint256_sub(temp_add_1, amount_out_c)
    let (local old_rp: Uint256, _) = uint256_mul(o_reserves.reserve_0, o_reserves.reserve_1)
    let (local new_rp: Uint256, _) = uint256_mul(new_reserve_0, new_reserve_1)
    let (valid) = uint256_le(old_rp, new_rp)
    assert_not_zero(valid)

    # update outcome reserces
    local o_reserves: OutcomeReserves
    assert o_reserves.reserve_0 = new_reserve_0
    assert o_reserves.reserve_1 = new_reserve_1
    outcome_reserves.write(market_id, o_reserves)

    return(1)
end

@external
func set_outcome{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(
        market_id: felt,
        outcome: felt,
    ) -> (success: felt):
    alloc_locals
    assert_not_zero(market_id)
    assert_nn_le(outcome, 2)

    # check market exists & is active (i.e. state = 1)
    let (local market) = markets.read(market_id=market_id)
    assert (market.state) = 1

    # check caller address is oracle address
    let (caller) = get_caller_address()
    assert (market.oracle_address) = caller

    # set outcome & expire market
    local updated_market: Market
    assert updated_market.creator_address = market.creator_address
    assert updated_market.oracle_address = market.oracle_address
    assert updated_market.state = 2
    assert updated_market.outcome = outcome

    return(1)
end

@external
func redeem_win{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(
        market_id: felt,
        to_address: felt,
    ) -> (success: felt):
    alloc_locals
    assert_not_zero(market_id)
    assert_not_zero(to_address)

    # check market exists & is expired (i.e. state == 2)
    let (local market) = markets.read(market_id=market_id)
    assert (market.state) = 2

    # check amount_in_0 & amount_in_1
    let (local token_0_id, local token_1_id) = _outcomeTokenIds(market_id)
    let (local contract_address) = get_contract_address()
    let (local o_reserves) = outcome_reserves.read(market_id=market_id)
    let (local balance_0: Uint256) = balances.read(token_id=token_0_id, account=contract_address)
    let (local balance_1: Uint256) = balances.read(token_id=token_1_id, account=contract_address)
    let (local amount_in_0: Uint256) = uint256_sub(balance_0, o_reserves.reserve_0)
    let (local amount_in_1: Uint256) = uint256_sub(balance_1, o_reserves.reserve_1)

    # burn received tokens
    _burn(contract_address, token_0_id, amount_in_0)
    _burn(contract_address, token_1_id, amount_in_1)

    # check win amount
    if market.outcome == 2:
        local two: Uint256
        assert two = Uint256(2,0)
        let (local first_half: Uint256, _) = uint256_unsigned_div_rem(amount_in_0, two)
        let (local second_half: Uint256, _) = uint256_unsigned_div_rem(amount_in_1, two)
        let (local win_amount: Uint256, _) = uint256_add(first_half, second_half)

        let (transfer_success) = IERC20.transfer(
            contract_address=WETH_ADDRESS,
            recipient=to_address,
            amount=win_amount
        )
        assert_not_zero(transfer_success)

        # update c reserve
        let (c_r: Uint256) = c_reserve.read()
        let (updated_c_r: Uint256) = uint256_sub(c_r, win_amount)
        c_reserve.write(updated_c_r)

        # rebinding ptrs, thus removing binding ambiguity
        tempvar range_check_ptr = range_check_ptr
        tempvar syscall_ptr = syscall_ptr
        tempvar pedersen_ptr = pedersen_ptr
    else:
        if market.outcome == 1:

            let (transfer_success) = IERC20.transfer(
                contract_address=WETH_ADDRESS,
                recipient=to_address,
                amount=amount_in_1
            )
            assert_not_zero(transfer_success)

            # update c reserve
            let (c_r: Uint256) = c_reserve.read()
            let (updated_c_r: Uint256) = uint256_sub(c_r, amount_in_1)
            c_reserve.write(updated_c_r)

            # rebinding ptrs, thus removing binding ambiguity
            tempvar range_check_ptr = range_check_ptr
            tempvar syscall_ptr = syscall_ptr
            tempvar pedersen_ptr = pedersen_ptr
        else:

            let (transfer_success) = IERC20.transfer(
                contract_address=WETH_ADDRESS,
                recipient=to_address,
                amount=amount_in_0
            )
            assert_not_zero(transfer_success)

            # update c reserve
            let (c_r: Uint256) = c_reserve.read()
            let (updated_c_r: Uint256) = uint256_sub(c_r, amount_in_0)
            c_reserve.write(updated_c_r)

            # rebinding ptrs, thus removing binding ambiguity
            tempvar range_check_ptr = range_check_ptr
            tempvar syscall_ptr = syscall_ptr
            tempvar pedersen_ptr = pedersen_ptr
        end
    end
    
    return (1)
end

@external
func transfer{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(
        recipient: felt,
        token_id: felt,
        amount: Uint256
    ) -> (success: felt):
    alloc_locals
    assert_not_zero(recipient)
    assert_not_zero(token_id)
    uint256_check(amount)

    let (sender) = get_caller_address()
    let (_success) = _transfer(sender, recipient, token_id, amount)

    return(_success)
end

@external
func transfer_from{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(
        sender: felt,
        recipient: felt,
        token_id: felt,
        amount: Uint256
    ) -> (success: felt):
    alloc_locals
    assert_not_zero(sender)
    assert_not_zero(recipient)
    assert_not_zero(token_id)
    uint256_check(amount)
    let (operator) = get_caller_address()

    # check approval 
    let (local operator_approval) = operator_approvals.read(owner=sender, operator=operator)
    assert_not_zero(operator_approval)


    let (_success) = _transfer(sender, recipient, token_id, amount)

    return(_success)
end

@external
func set_approval_for_all{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(
        operator: felt,
        approved: felt
    ) -> (success: felt):
    assert_not_zero(operator)
    assert_nn_le(approved, 1)

    let (owner) = get_caller_address()
    operator_approvals.write(owner, operator, approved)

    return(1)
end

#
# Internals
#

func _outcomeTokenIds{
        pedersen_ptr : HashBuiltin*,
    }(
        market_id: felt
    ) -> (token_0_id: felt, token_1_id: felt):
    alloc_locals
    assert_not_zero(market_id)

    let (local id_0) = hash2{hash_ptr=pedersen_ptr}(market_id, 1)
    let (id_1) = hash2{hash_ptr=pedersen_ptr}(market_id, 2)

    return (id_0, id_1)
end

func _transfer{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(
        sender: felt, 
        recipient: felt, 
        token_id: felt,
        amount: Uint256 
    ) -> (success: felt):
    alloc_locals
    assert_not_zero(sender)
    assert_not_zero(recipient)
    assert_not_zero(token_id)
    uint256_check(amount)

    # get sender's balance
    let (local sender_balance: Uint256) = balances.read(token_id=token_id, account=sender)

    # validates amount <= sender_balance and returns 1 if true
    let (enough_balance) = uint256_le(amount, sender_balance)
    assert_not_zero(enough_balance)

    # subtract from sender
    let (new_sender_balance: Uint256) = uint256_sub(sender_balance, amount)
    balances.write(token_id, sender, new_sender_balance)

    # add to recipient
    let (recipient_balance: Uint256) = balances.read(token_id=token_id, account=recipient)
    let (new_recipient_balance: Uint256, _) = uint256_add(recipient_balance, amount)
    balances.write(token_id, recipient, new_recipient_balance)

    return(1)
end

func _mint{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(account: felt, token_id: felt, amount: Uint256) -> (success: felt):
    alloc_locals
    assert_not_zero(account)
    assert_not_zero(token_id)
    uint256_check(amount)

    let (balance: Uint256) = balances.read(token_id=token_id, account=account)

    # mint
    let (new_balance: Uint256, is_overflow) = uint256_add(balance, amount)
    assert (is_overflow) = 0
    balances.write(token_id, account, new_balance)

    return (1)
end

func _burn{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(account: felt, token_id: felt, amount: Uint256) -> (success: felt):
    alloc_locals
    assert_not_zero(account)
    assert_not_zero(token_id)
    uint256_check(amount)

    let (balance: Uint256) = balances.read(token_id=token_id, account=account)

    # validates amount <= balance and returns 1 if true
    let (enough_balance) = uint256_le(amount, balance)
    assert_not_zero(enough_balance)
    
    let (new_balance: Uint256) = uint256_sub(balance, amount)
    balances.write(token_id, account, new_balance)

    return (1)
end



# - only 3 states (0 -> nothing, 1 -> trading, 2 -> closed)
# - market identifier is given
# - ERC1155 is implemented right here
# - only one collateral token allowed (i.e. WETH)
# - shared oracle config
# - markets are live for 7 days
