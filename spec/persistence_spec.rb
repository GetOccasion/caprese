require 'spec_helper'

describe 'Requests that persist data', type: :request do
  let!(:resource) do
    create :post
  end

  let!(:user) do
    create :user
  end

  describe '#create' do
    before do
      post "/api/v1/#{type}/", params: { data: data }
    end

    subject(:type) { 'comments' }
    subject(:data_type) { type }
    subject(:attributes) { {} }
    subject(:relationships) { {} }
    subject(:data) do
      output = { type: data_type }
      output.merge!(attributes: attributes)
      output.merge!(relationships: relationships)
    end

    subject(:attributes) do
      {
        body: 'unique_body'
      }
    end

    subject(:relationships) do
      {
        user: { data: { type: 'users', id: user.id } },
        post: { data: { type: 'posts', id: resource.id } }
      }
    end

    it 'creates the record' do
      expect(Comment.count).to eq(1)
    end

    it 'assigns attributes' do
      expect(Comment.last.body).to eq('unique_body')
    end

    it 'assigns relationships' do
      expect(Comment.last.post).to eq(resource)
      expect(Comment.last.user).to eq(user)
    end

    context 'when data is an array' do
      subject(:data) { [{ id: '2', type: 'posts' }] }

      it 'responds with 422' do
        expect(response.status).to eq(422)
      end

      it 'responds with error source pointer to data' do
        expect(json['errors'][0]['source']['pointer']).to eq('/data')
      end
    end

    context 'when has_many field' do
      subject(:type) { 'posts' }
      let!(:comments) { create_list :comment, 2 }

      subject(:attributes) do
        {
          title: 'unique_title'
        }
      end

      subject(:relationships) do
        {
          comments: { data: [
            { type: 'comments', id: comments[0].id.to_s },
            { type: 'comments', id: comments[1].id.to_s }
          ]},
          user: {
            data: {
              type: 'users',
              id: create(:user).id.to_s
            }
          }
        }
      end

      it 'creates the record' do
        expect(Post.last.comments.count).to eq(2)
      end

      it 'assigns relationships' do
        expect(Comment.last(2)[0].post).to eq(Post.last)
        expect(Comment.last(2)[1].post).to eq(Post.last)
      end
    end

    context 'when type is invalid' do
      subject(:data_type) { '' }

      it 'responds with primary data error' do
        expect(json['errors'][0]['source']).to eq({ 'pointer' => '/data/type' })
      end
    end

    context 'when attributes are invalid' do
      subject(:attributes) { {} }

      subject(:relationships) do
        {
          post: { data: { type: 'posts', id: resource.id } },
          user: { data: { type: 'users', id: user.id } }
        }
      end

      it 'fails to create the record with errors' do
        expect(json['errors'][0]['source']['pointer']).to eq('/data/attributes/body')
      end
    end

    context 'when relationships are invalid' do
      context 'data' do
        context 'missing' do
          subject(:relationships) do
            {
              post: { type: 'posts', id: resource.id },
              user: { data: { type: 'users', id: user.id } }
            }
          end

          it 'fails with error pointer to the relationship /data' do
            expect(json['errors'][0]['source']['pointer']).to eq('/data/relationships/post/data')
          end
        end

        context 'plurality mismatch' do
          subject(:relationships) do
            {
              post: { data: [{type: 'posts', id: resource.id }] },
              user: { data: { type: 'users', id: user.id } }
            }
          end

          it 'fails with error pointer to the relationship /data' do
            expect(json['errors'][0]['source']['pointer']).to eq('/data/relationships/post/data')
          end
        end
      end

      context 'id' do
        subject(:relationships) do
          {
            post: { data: { type: 'posts', id: resource.id + 10000 } },
            user: { data: { type: 'users', id: user.id } }
          }
        end

        it 'fails with errors' do
          expect(json['errors'][0]['code']).to eq('not_found')
        end
      end

      context 'type' do
        subject(:relationships) do
          {
            post: { data: { id: resource.id } },
            user: { data: { type: 'users', id: user.id } }
          }
        end

        it 'fails with error' do
          expect(json['errors'][0]['source']['pointer']).to eq('/data/relationships/post/data/type')
        end
      end
    end

    context 'when creating with autosave associations' do
      subject(:attributes) do
        {
          body: 'unique_body'
        }
      end

      subject(:relationships) do
        {
          user: { data: { type: 'users', id: user.id } },
          post: {
            data: {
              type: 'posts',
              attributes: {
                title: 'A post title'
              },
              relationships: {
                user: { data: { type: 'users', id: user.id } }
              }
            }
          }
        }
      end

      it 'creates the record' do
        expect(Comment.count).to eq(1)
      end

      it 'creates the autosave association with attributes' do
        expect(Comment.first.post.title).to eq('A post title')
      end

      it 'creates the autosave association with relationships' do
        expect(Comment.first.post.user).to eq(user)
      end

      context 'when nested relationship of relationship is invalid' do
        context 'autosaving' do
          subject(:relationships) do
            {
              user: { data: { type: 'users', id: user.id } },
              post: {
                data: {
                  type: 'posts',
                  attributes: {
                    title: 'A post title'
                  },
                  relationships: {
                    user: {
                      data: {
                        type: 'users',
                        attributes: {
                          name: ''
                        }
                      }
                    }
                  }
                }
              }
            }
          end

          it 'correctly points to the attribute that caused the error' do
            expect(json['errors'][0]['source']['pointer']).to eq('/data/relationships/post/data/relationships/user/data/attributes/name')
          end
        end

        context 'validates_associated' do
          subject(:relationships) do
            {
              user: { data: { type: 'users', id: user.id } },
              post: { data: { type: 'posts', id: resource.id } },
              rating: {
                data: {
                  type: 'ratings',
                  attributes: {
                    value: nil
                  }
                }
              }
            }
          end

          it 'correctly points to the attribute that caused the error' do
            expect(json['errors'][0]['source']['pointer']).to eq('/data/relationships/rating/data/attributes/value')
          end

          it 'propagates nested error options' do
            expect(json['errors'][0]['detail']).to eq(I18n.t('api.v1.errors.models.comment.rating.value.invalid', custom_val: '123'))
          end
        end
      end
    end
  end

  describe '#update' do
    before { put "/api/v1/#{type}/#{existing_resource.id}", params: { data: data } }

    subject(:type) { 'comments' }
    subject(:existing_resource) { create(:comment, user: user, post: resource) }
    subject(:attributes) { {} }
    subject(:relationships) { {} }
    subject(:data) do
      output = { type: type }
      output.merge!(attributes: attributes)
      output.merge!(relationships: relationships)
    end

    context 'when data is an array' do
      subject(:data) { [{ id: '2', type: 'posts' }] }

      it 'responds with 422' do
        expect(response.status).to eq(422)
      end

      it 'responds with error source pointer to data' do
        expect(json['errors'][0]['source']['pointer']).to eq('/data')
      end
    end

    context 'valid' do
      context 'attributes' do
        subject(:attributes) do
          {
            body: 'unique_body2'
          }
        end

        it 'updates the record' do
          expect(Comment.last.body).to eq('unique_body2')
        end
      end

      context 'relationships' do
        let!(:other_user) { create :user }

        subject(:relationships) do
          {
            user: { data: { type: 'users', id: other_user.id } }
          }
        end

        it 'updates the record' do
          expect(Comment.last.user).to eq(other_user)
        end

        context 'setting nil' do
          subject(:existing_resource) { create(:comment, :with_rating, user: user, post: resource) }

          subject(:relationships) do
            {
              rating: { data: nil }
            }
          end

          it 'updates the record' do
            expect(Comment.last.rating).to be_nil
          end
        end
      end
    end

    context 'invalid' do
      context 'attributes' do
        subject(:attributes) do
          {
            body: ''
          }
        end

        it 'fails to create the record with errors' do
          expect(json['errors'][0]['source']['pointer']).to eq('/data/attributes/body')
        end
      end

      context 'callback' do
        subject(:attributes) do
          {
            body: 'trigger_callback'
          }
        end

        it 'fails to create the record with errors' do
          expect(json['errors'][0]['source']['pointer']).to eq('/data/attributes/body')
        end
      end

      context 'relationships' do
        subject(:relationships) do
          {
            user: { data: { type: 'users', id: user.id + 10000 } }
          }
        end

        it 'fails to create the record with errors' do
          expect(json['errors'][0]['code']).to eq('not_found')
        end
      end
    end

    context 'autosaving relationship' do
      let(:type) { 'posts' }
      let(:existing_resource) do
        if @added_comments.blank?
          create_list(:comment, 2, post: resource)
          @added_comments = true
        end

        resource
      end

      subject(:relationships) do
        {
          comments: {
            data: [
              {
                type: 'comments',
                attributes: {
                  body: body
                }
              }
            ]
          }
        }
      end

      let(:body) { 'Unique body!' }

      it 'updates relationships' do
        expect(existing_resource.comments.length).to eq(1)
        expect(existing_resource.comments.last.body).to eq(body)
      end

      context 'when invalid' do
        let(:body) { '' }

        it 'responds with 422' do
          expect(response.status).to eq(422)
        end

        it 'responds with error pointer to relationship field' do
          expect(json['errors'][0]['source']['pointer']).to eq('/data/relationships/comments/data/attributes/body')
        end

        it 'does not update relationship' do
          expect(existing_resource.comments.length).to eq(2)
        end
      end
    end
  end

  describe '#destroy' do
    before { delete "/api/v1/#{destroying.class.name.underscore.pluralize}/#{destroying.id}" }

    context 'when resource can be deleted' do
      subject(:destroying) { create(:comment, user: user, post: resource) }

      it 'deletes the resource' do
        expect(Comment.count).to eq(0)
      end
    end

    context 'when resource cannot be deleted' do
      subject(:destroying) { create(:user) }

      it 'responds with 403' do
        expect(response.status).to eq(403)
      end
    end
  end
end
