class Post < ApplicationRecord
  belongs_to :user, autosave: true

  has_many :comments

  validates_presence_of :title
end
