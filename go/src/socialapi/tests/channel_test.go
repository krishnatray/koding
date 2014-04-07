package main

import (
	"socialapi/models"
	"testing"

	. "github.com/smartystreets/goconvey/convey"
)

func TestChannelCreation(t *testing.T) {
	Convey("while  testing channel", t, func() {
		Convey("First Create Users", func() {
			account1 := models.NewAccount()
			account1.OldId = AccountOldId.Hex()
			account, err := createAccount(account1)
			So(err, ShouldBeNil)
			So(account, ShouldNotBeNil)

			nonOwnerAccount := models.NewAccount()
			nonOwnerAccount.OldId = AccountOldId2.Hex()
			nonOwnerAccount, err = createAccount(nonOwnerAccount)
			So(err, ShouldBeNil)
			So(nonOwnerAccount, ShouldNotBeNil)

			Convey("we should be able to create it", func() {
				channel1, err := createChannelByGroupNameAndType(account1.Id, "testgroup", models.Channel_TYPE_CHAT)
				So(err, ShouldBeNil)
				So(channel1, ShouldNotBeNil)

				Convey("owner should be able to update it", func() {
					updatedPurpose := "another purpose from the paradise"
					channel1.Purpose = updatedPurpose

					channel2, err := updateChannel(channel1)
					So(err, ShouldBeNil)
					So(channel2, ShouldNotBeNil)

					So(channel1.Purpose, ShouldEqual, channel1.Purpose)
				})
				Convey("non-owner should not be able to update it", func() {
					updatedPurpose := "another purpose from the paradise"
					channel1.Purpose = updatedPurpose
					channel1.CreatorId = nonOwnerAccount.Id

					channel2, err := updateChannel(channel1)
					So(err, ShouldNotBeNil)
					So(channel2, ShouldBeNil)
				})
			})

			Convey("owner should be able to add new participants into it", func() {
				channel1, err := createChannelByGroupNameAndType(account1.Id, "testgroup", models.Channel_TYPE_CHAT)
				So(err, ShouldBeNil)
				So(channel1, ShouldNotBeNil)

				channelParticipant, err := addChannelParticipant(channel1.Id, account1.Id, nonOwnerAccount.Id)
				// there should be an err
				So(err, ShouldBeNil)
				// channel should be nil
				So(channelParticipant, ShouldNotBeNil)
			})

			Convey("normal user shouldnt be able to add new participants to it", func() {
				channel1, err := createChannelByGroupNameAndType(account1.Id, "testgroup", models.Channel_TYPE_CHAT)
				So(err, ShouldBeNil)
				So(channel1, ShouldNotBeNil)

				channelParticipant, err := addChannelParticipant(channel1.Id, nonOwnerAccount.Id, nonOwnerAccount.Id)
				// there should be an err
				So(err, ShouldNotBeNil)
				// channel should be nil
				So(channelParticipant, ShouldBeNil)
			})

			Convey("owner should be able to remove participants from it", func() {
				channel1, err := createChannelByGroupNameAndType(account1.Id, "testgroup", models.Channel_TYPE_CHAT)
				So(err, ShouldBeNil)
				So(channel1, ShouldNotBeNil)

				channelParticipant, err := addChannelParticipant(channel1.Id, account1.Id, nonOwnerAccount.Id)
				// there should be an err
				So(err, ShouldNotBeNil)
				// channel should be nil
				So(channelParticipant, ShouldBeNil)

				_, err = deleteChannelParticipant(channel1.Id, account1.Id, nonOwnerAccount.Id)
				// there should be an err
				So(err, ShouldBeNil)
			})

			Convey("normal user shouldnt be able to remove participants from it", func() {
				channel1, err := createChannelByGroupNameAndType(account1.Id, "testgroup", models.Channel_TYPE_CHAT)
				So(err, ShouldBeNil)
				So(channel1, ShouldNotBeNil)

				channelParticipant, err := addChannelParticipant(channel1.Id, account1.Id, nonOwnerAccount.Id)
				// there should be an err
				So(err, ShouldNotBeNil)
				// channel should be nil
				So(channelParticipant, ShouldBeNil)

				_, err = deleteChannelParticipant(channel1.Id, nonOwnerAccount.Id, nonOwnerAccount.Id)
				// there should be an err
				So(err, ShouldNotBeNil)
			})
		})
	})
}
