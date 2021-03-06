# == Schema Information
#
# Table name: users
#
#  id            :integer          not null, primary key
#  secret        :string
#  token         :string
#  uid           :string
#  name          :string
#  image         :string
#  session_token :string
#  nickname      :string
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#

class User < ActiveRecord::Base
  validates :uid, :name, presence: true
  has_many :out_profiles, class_name: 'Profile', foreign_key: :follower_id
  has_many :in_profiles, class_name: 'Profile', foreign_key: :followee_id

  before_validation do
    self.session_token ||= SecureRandom.hex
  end

  def self.find_with_omniauth(omniauth_hash)
    user = User.find_by(uid: omniauth_hash[:uid])
    return user if user
    User.create!({
      uid: omniauth_hash.fetch(:uid),
      secret: omniauth_hash.fetch(:credentials).fetch(:secret),
      token: omniauth_hash.fetch(:credentials).fetch(:token),
      name: omniauth_hash.fetch(:info).fetch(:name),
      nickname: omniauth_hash.fetch(:info).fetch(:nickname),
      image: omniauth_hash.fetch(:info).fetch(:image),
    })
  end

  def reset_session_token!
    self.session_token = SecureRandom.hex
    self.save
    session_token
  end

  def twitter_client
    @client ||= begin
      Twitter::REST::Client.new do |config|
        config.consumer_key        = ENV['TWITTER_KEY']
        config.consumer_secret     = ENV['TWITTER_SECRET']
        config.access_token        = token
        config.access_token_secret = secret
      end
    end
  end

  def twitter_friends
    @friends ||= twitter_client.friends
  end

  def twitter_followers
    @followers ||= twitter_client.followers
  end

  def twitter_follower_ids
    @twitter_follower_ids ||= twitter_client.follower_ids.map { |f| f }
  end

  def twitter_friend_ids
    @twitter_friend_ids ||= twitter_client.friend_ids.map { |f| f }
  end

  def update_out_profiles2
    twitter_friend_ids.each do |friend_id|
      puts "Checking out #{ friend_id }"
      if !profile_exists_for?(friend_id)
        create_out_profile_for(friend_id)
      elsif !out_profile_exists_for?(friend_id)
        update_to_out_profile_for(friend_id)
      end
    end
    puts "Unfollowed people"
    no_longer_following_uids.each do |not_friend_id|
      pro = Profile.find_by(follower_id: id, uid: not_friend_id)
      puts "Unfollowed #{ pro.name }"
      pro.update(following_now: false, unfollowed_at: Date.current)
    end
  end

  def update_in_profiles2
    twitter_follower_ids.each do |follower_id|
      puts "Checking out #{ follower_id }"
      if !profile_exists_for?(follower_id)
        create_in_profile_for(follower_id)
      elsif !in_profile_exists_for?(follower_id)
        update_to_in_profile_for(follower_id)
      end
    end
    puts "Unfollowed me"
    no_longer_followed_by_uids.each do |not_follower_id|
      pro = Profile.find_by(followee_id: id, uid: not_follower_id)
      puts "Unfollowed #{ pro.name }"
      pro.update(following_me_now: false, unfollowed_me_at: Date.current)
    end
  end

  def update_to_out_profile_for(friend_id)
    pro = Profile.find_by(followee_id: id, uid: friend_id)
    pro.update({
      follower_id: id,
      following_now: true,
      followed_at: Date.current
    })
  end

  def update_to_in_profile_for(follower_id)
    pro = Profile.find_by(follower_id: id, uid: follower_id)
    pro.update({
      followee_id: id,
      following_me_now: true,
      followed_me_at: Date.current
    })
  end

  def out_profile_uids
    Profile.where(follower_id: id, following_now: true).pluck(:uid).map(&:to_i)
  end

  def in_profile_uids
    Profile.where(followee_id: id, following_me_now: true).pluck(:uid).map(&:to_i)
  end

  def no_longer_following_uids
    out_profile_uids - twitter_friend_ids
  end

  def no_longer_followed_by_uids
    in_profile_uids - twitter_follower_ids
  end

  def create_in_profile_for(friend_id)
    raise "Invalid Friend Id: #{ friend_id }" unless friend_id.is_a?(Integer)

    user = twitter_client.user(friend_id)
    Profile.create({
      followee_id: id,
      followed_me_at: Date.current,
      uid: user.id.to_s,
      name: user.name,
      screen_name: user.screen_name,
      location: user.location,
      description: user.description,
      lang: user.lang,
      following_me_now: true,
      followers_count: user.followers_count,
      friends_count: user.friends_count,
      favorites_count: user.favourites_count,
      listed_count: user.listed_count,
      statuses_count: user.statuses_count
    })
  end

  def create_out_profile_for(friend_id)
    raise "Invalid Friend Id: #{ friend_id }" unless friend_id.is_a?(Integer)

    user = twitter_client.user(friend_id)
    Profile.create({
      follower_id: id,
      followed_at: Date.current,
      uid: user.id.to_s,
      name: user.name,
      screen_name: user.screen_name,
      location: user.location,
      description: user.description,
      lang: user.lang,
      following_now: true,
      followed_before: true,
      followers_count: user.followers_count,
      friends_count: user.friends_count,
      favorites_count: user.favourites_count,
      listed_count: user.listed_count,
      statuses_count: user.statuses_count
    })
  end

  def out_profile_exists_for?(profile_id)
    Profile.exists?(
      ['uid = ? AND follower_id = ?', profile_id.to_s, id]
    )
  end

  def in_profile_exists_for?(profile_id)
    Profile.exists?(
      ['uid = ? AND followee_id = ?', profile_id.to_s, id]
    )
  end

  def profile_exists_for?(profile_id)
    Profile.exists?(
      ['uid = ? AND (follower_id = ? OR followee_id = ?)', profile_id.to_s, id, id]
    )
  end
end
