package genmsg_test

import (
	"testing"

	tmproto "github.com/cometbft/cometbft/proto/tendermint/types"
	codectypes "github.com/cosmos/cosmos-sdk/codec/types"
	sdk "github.com/cosmos/cosmos-sdk/types"
	banktypes "github.com/cosmos/cosmos-sdk/x/bank/types"
	"github.com/stretchr/testify/require"

	"github.com/NibiruChain/nibiru/v2/app"
	"github.com/NibiruChain/nibiru/v2/x/common/testutil/testapp"
	"github.com/NibiruChain/nibiru/v2/x/genmsg"
	v1 "github.com/NibiruChain/nibiru/v2/x/genmsg/v1"
)

func TestGenmsgInGenesis(t *testing.T) {
	senderAddr := sdk.AccAddress("sender")
	recvAddr := sdk.AccAddress("recv")

	encoding := app.MakeEncodingConfig()
	appGenesis := app.GenesisState{}
	appGenesis[banktypes.ModuleName] = encoding.Codec.MustMarshalJSON(
		&banktypes.GenesisState{
			Balances: []banktypes.Balance{
				{
					Address: senderAddr.String(),
					Coins:   sdk.NewCoins(sdk.NewInt64Coin("unibi", 100000)),
				},
			},
		},
	)

	testMsg := &banktypes.MsgSend{
		FromAddress: senderAddr.String(),
		ToAddress:   recvAddr.String(),
		Amount:      sdk.NewCoins(sdk.NewInt64Coin("unibi", 1000)),
	}

	anyMsg, err := codectypes.NewAnyWithValue(testMsg)
	require.NoError(t, err)

	appGenesis[genmsg.ModuleName] = encoding.Codec.MustMarshalJSON(
		&v1.GenesisState{
			Messages: []*codectypes.Any{anyMsg},
		},
	)

	app, _ := testapp.NewNibiruTestApp(appGenesis)
	ctx := app.NewContext(false, tmproto.Header{
		Height: 1,
	})

	balance, err := app.BankKeeper.Balance(ctx, &banktypes.QueryBalanceRequest{
		Address: recvAddr.String(),
		Denom:   "unibi",
	})
	require.NoError(t, err)
	require.True(t, balance.Balance.Equal(sdk.NewInt64Coin("unibi", 1000)))
}
