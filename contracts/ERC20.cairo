%lang starknet
%builtins pedersen range_check ecdsa

from starkware.cairo.common.cairo_builtins import HashBuiltin, SignatureBuiltin
from starkware.cairo.common.math import assert_not_zero
from starkware.cairo.common.uint256 import (
    Uint256, uint256_add, uint256_sub, uint256_le, uint256_lt, uint256_check
)
from starkware.starknet.common.syscalls import call_contract, get_tx_signature, get_contract_address, get_caller_address

# ref from - https://github.com/OpenZeppelin/cairo-contracts/blob/main/contracts/token/ERC20.cairo

#
# Storage
#

@storage_var
func name() -> (res: felt):
end

@storage_var
func symbol() -> (res: felt):
end

@storage_var
func decimals() -> (res: felt):
end

@storage_var
func total_supply() -> (res: Uint256):
end

@storage_var
func balances(account: felt) -> (res: Uint256):
end

@storage_var
func allowances(owner: felt, spender: felt) -> (res: Uint256):
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
        _name: felt,
        _symbol: felt,
        _initial_supply: Uint256,
        _recipient: felt
    ):
    name.write(_name)
    symbol.write(_symbol)
    decimals.write(18)
    _mint(_recipient, _initial_supply)
    return ()
end

#
# Getters
#

@view
func get_name{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }() -> (name: felt):
    let (n) = name.read()
    return (n)
end

@view
func get_symbol{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }() -> (symbol: felt):
    let (_symbol) = symbol.read()
    return (_symbol)
end

@view
func get_total_supply{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }() -> (totalSupply: Uint256):
    let (_totalSupply: Uint256) = total_supply.read()
    return (_totalSupply)
end

@view
func get_decimals{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }() -> (decimals: felt):
    let (_decimals) = decimals.read()
    return (_decimals)
end

@view
func balance_of{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(account: felt) -> (balance: Uint256):
    let (_balance: Uint256) = balances.read(account=account)
    return (_balance)
end

@view
func allowance{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(owner: felt, spender: felt) -> (remaining: Uint256):
    let (_remaining: Uint256) = allowances.read(owner=owner, spender=spender)
    return (_remaining)
end

#
# Internals
#
func _mint{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(recipient: felt, amount: Uint256) -> (success: felt):
    alloc_locals
    assert_not_zero(recipient)
    uint256_check(amount)

    let (balance: Uint256) = balances.read(account=recipient)

    # mint
    # no need of overflow check here, since total supply overflow check takes care of it
    let (new_balance: Uint256, _) = uint256_add(balance, amount)
    balances.write(recipient, new_balance)

    # increase total supply
    let (local supply: Uint256) = total_supply.read()
    let (local new_supply: Uint256, is_overflow) = uint256_add(supply, amount)
    assert (is_overflow) = 0
    total_supply.write(new_supply)

    return (1)
end

func _transfer{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(
        sender: felt, 
        recipient: felt, 
        amount: Uint256 
    ) -> (success: felt):
    alloc_locals
    assert_not_zero(sender)
    assert_not_zero(recipient)
    uint256_check(amount)

    # get sender's balance
    let (local sender_balance: Uint256) = balances.read(account=sender)

    # validates amount <= sender_balance and returns 1 if true
    let (enough_balance) = uint256_le(amount, sender_balance)
    assert_not_zero(enough_balance)

    # subtract from sender
    let (new_sender_balance: Uint256) = uint256_sub(sender_balance, amount)
    balances.write(sender, new_sender_balance)

    # add to recipient
    let (recipient_balance: Uint256) = balances.read(account=recipient)
    # overflow is not possible because sum is guaranteed by mint to be less than total supply
    let (new_recipient_balance: Uint256, _) = uint256_add(recipient_balance, amount)
    balances.write(recipient, new_recipient_balance)

    return(1)
end

func _burn{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(account: felt, amount: Uint256) -> (success: felt):
    alloc_locals
    assert_not_zero(account)
    uint256_check(amount)

    let (balance: Uint256) = balances.read(account)

    # validates amount <= balance and returns 1 if true
    let (enough_balance) = uint256_le(amount, balance)
    assert_not_zero(enough_balance)
    
    let (new_balance: Uint256) = uint256_sub(balance, amount)
    balances.write(account, new_balance)

    let (supply: Uint256) = total_supply.read()
    let (new_supply: Uint256) = uint256_sub(supply, amount)
    total_supply.write(new_supply)

    return (1)
end


# 
# Externals
#

func transfer{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(
        recipient: felt, 
        amount: Uint256
    ) -> (success: felt):
    alloc_locals
    assert_not_zero(recipient)
    uint256_check(amount)

    let (sender) = get_caller_address()
    let (success) = _transfer(sender, recipient, amount)

    return (success)
end

func transfer_from{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(
        sender: felt, 
        recipient: felt, 
        amount: Uint256
    ) -> (success: felt):
    alloc_locals
    assert_not_zero(sender)
    assert_not_zero(recipient)
    let (caller) = get_caller_address()

    let (local caller_allowance: Uint256) = allowances.read(owner=sender, spender=caller)

    # validates amount <= caller_allowance and returns 1 if true   
    let (enough_allowance) = uint256_le(amount, caller_allowance)
    assert_not_zero(enough_allowance)

    let (success) = _transfer(sender, recipient, amount)
    assert_not_zero(success)

    # subtract allowance
    let (new_allowance: Uint256) = uint256_sub(caller_allowance, amount)
    allowances.write(sender, caller, new_allowance)

    return(1)
end

func approve{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(caller: felt, spender: felt, amount: Uint256) -> (success: felt):
    assert_not_zero(caller)
    assert_not_zero(spender)
    uint256_check(amount)
    allowances.write(caller, spender, amount)
    return (1)
end