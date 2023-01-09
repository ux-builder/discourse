# frozen_string_literal: true

RSpec.describe HashtagAutocompleteService do
  fab!(:user) { Fabricate(:user) }
  fab!(:category1) { Fabricate(:category, name: "The Book Club", slug: "the-book-club") }
  fab!(:tag1) { Fabricate(:tag, name: "great-books", topic_count: 22) }
  fab!(:topic1) { Fabricate(:topic) }
  let(:guardian) { Guardian.new(user) }

  subject { described_class.new(guardian) }

  after { DiscoursePluginRegistry.reset! }

  describe ".contexts_with_ordered_types" do
    it "returns a hash of all the registrered search contexts and their types in the defined priority order" do
      expect(HashtagAutocompleteService.contexts_with_ordered_types).to eq(
        { "topic-composer" => %w[category tag] },
      )
      DiscoursePluginRegistry.register_hashtag_autocomplete_contextual_type_priority(
        { type: "category", context: "awesome-composer", priority: 50 },
        stub(enabled?: true),
      )
      DiscoursePluginRegistry.register_hashtag_autocomplete_contextual_type_priority(
        { type: "tag", context: "awesome-composer", priority: 100 },
        stub(enabled?: true),
      )
      expect(HashtagAutocompleteService.contexts_with_ordered_types).to eq(
        { "topic-composer" => %w[category tag], "awesome-composer" => %w[tag category] },
      )
    end
  end

  describe ".data_source_icons" do
    it "gets an array for all icons defined by data sources so they can be used for markdown allowlisting" do
      expect(HashtagAutocompleteService.data_source_icons).to eq(%w[folder tag])
    end
  end

  describe "#search" do
    it "returns search results for tags and categories by default" do
      expect(subject.search("book", %w[category tag]).map(&:text)).to eq(
        ["The Book Club", "great-books"],
      )
    end

    it "respects the types_in_priority_order param" do
      expect(subject.search("book", %w[tag category]).map(&:text)).to eq(
        ["great-books", "The Book Club"],
      )
    end

    it "respects the limit param" do
      expect(subject.search("book", %w[tag category], limit: 1).map(&:text)).to eq(["great-books"])
    end

    it "does not allow more than SEARCH_MAX_LIMIT results to be specified by the limit param" do
      stub_const(HashtagAutocompleteService, "SEARCH_MAX_LIMIT", 1) do
        expect(subject.search("book", %w[category tag], limit: 1000).map(&:text)).to eq(
          ["The Book Club"],
        )
      end
    end

    it "does not search other data sources if the limit is reached by earlier type data sources" do
      # only expected once to try get the exact matches first
      DiscourseTagging.expects(:filter_allowed_tags).never
      subject.search("the-book", %w[category tag], limit: 1)
    end

    it "includes the tag count" do
      tag1.update!(topic_count: 78)
      expect(subject.search("book", %w[tag category]).map(&:text)).to eq(
        ["great-books", "The Book Club"],
      )
    end

    it "does case-insensitive search" do
      expect(subject.search("bOOk", %w[category tag]).map(&:text)).to eq(
        ["The Book Club", "great-books"],
      )
    end

    it "can search categories by name or slug" do
      expect(subject.search("the-book-club", %w[category]).map(&:text)).to eq(["The Book Club"])
      expect(subject.search("Book C", %w[category]).map(&:text)).to eq(["The Book Club"])
    end

    it "does not include categories the user cannot access" do
      category1.update!(read_restricted: true)
      expect(subject.search("book", %w[tag category]).map(&:text)).to eq(["great-books"])
    end

    it "does not include tags the user cannot access" do
      Fabricate(:tag_group, permissions: { "staff" => 1 }, tag_names: ["great-books"])
      expect(subject.search("book", %w[tag]).map(&:text)).to be_empty
    end

    it "includes other data sources" do
      Fabricate(:bookmark, user: user, name: "read review of this fantasy book")
      Fabricate(:bookmark, user: user, name: "cool rock song")
      guardian.user.reload

      DiscoursePluginRegistry.register_hashtag_autocomplete_data_source(
        FakeBookmarkHashtagDataSource,
        stub(enabled?: true),
      )

      expect(subject.search("book", %w[category tag bookmark]).map(&:text)).to eq(
        ["The Book Club", "great-books", "read review of this fantasy book"],
      )
    end

    it "handles refs for categories that have a parent" do
      parent = Fabricate(:category, name: "Hobbies", slug: "hobbies")
      category1.update!(parent_category: parent)
      expect(subject.search("book", %w[category tag]).map(&:ref)).to eq(
        %w[hobbies:the-book-club great-books],
      )
      category1.update!(parent_category: nil)
    end

    it "appends type suffixes for the ref on conflicting slugs on items that are not the top priority type" do
      Fabricate(:tag, name: "the-book-club")
      expect(subject.search("book", %w[category tag]).map(&:ref)).to eq(
        %w[the-book-club great-books the-book-club::tag],
      )

      Fabricate(:bookmark, user: user, name: "book club")
      guardian.user.reload

      DiscoursePluginRegistry.register_hashtag_autocomplete_data_source(
        FakeBookmarkHashtagDataSource,
        stub(enabled?: true),
      )

      expect(subject.search("book", %w[category tag bookmark]).map(&:ref)).to eq(
        %w[book-club the-book-club great-books the-book-club::tag],
      )
    end

    it "orders results by (with type ordering within each section):
        1. exact match on slug (ignoring parent/child distinction for categories)
        2. slugs that start with the term
        3. then name for everything else" do
      category2 = Fabricate(:category, name: "Book Library", slug: "book-library")
      Fabricate(:category, name: "Horror", slug: "book", parent_category: category2)
      Fabricate(:category, name: "Romance", slug: "romance-books")
      Fabricate(:category, name: "Abstract Philosophy", slug: "abstract-philosophy-books")
      category6 = Fabricate(:category, name: "Book Reviews", slug: "book-reviews")
      Fabricate(:category, name: "Good Books", slug: "book", parent_category: category6)

      Fabricate(:tag, name: "bookmania", topic_count: 15)
      Fabricate(:tag, name: "awful-books", topic_count: 56)

      expect(subject.search("book", %w[category tag]).map(&:ref)).to eq(
        [
          "book-reviews:book", # category exact match on slug, name sorted
          "book-library:book",
          "book-library", # category starts with match on slug, name sorted
          "book-reviews",
          "bookmania", # tag starts with match on slug, name sorted
          "abstract-philosophy-books", # category partial match on slug, name sorted
          "romance-books",
          "the-book-club",
          "awful-books", # tag partial match on slug, name sorted
          "great-books",
        ],
      )
      expect(subject.search("book", %w[category tag]).map(&:text)).to eq(
        [
          "Good Books",
          "Horror",
          "Book Library",
          "Book Reviews",
          "bookmania",
          "Abstract Philosophy",
          "Romance",
          "The Book Club",
          "awful-books",
          "great-books",
        ],
      )
    end

    context "when multiple tags and categories are returned" do
      fab!(:category2) { Fabricate(:category, name: "Book Zone", slug: "book-zone") }
      fab!(:category3) { Fabricate(:category, name: "Book Dome", slug: "book-dome") }
      fab!(:category4) { Fabricate(:category, name: "Bookworld", slug: "book") }
      fab!(:tag2) { Fabricate(:tag, name: "mid-books") }
      fab!(:tag3) { Fabricate(:tag, name: "terrible-books") }
      fab!(:tag4) { Fabricate(:tag, name: "book") }

      it "orders them by name within their type order" do
        expect(subject.search("book", %w[category tag], limit: 10).map(&:ref)).to eq(
          %w[book book::tag book-dome book-zone the-book-club great-books mid-books terrible-books],
        )
      end

      it "prioritises exact matches to the top of the list" do
        expect(subject.search("book", %w[category tag], limit: 10).map(&:ref)).to eq(
          %w[book book::tag book-dome book-zone the-book-club great-books mid-books terrible-books],
        )
      end
    end

    context "when not tagging_enabled" do
      before { SiteSetting.tagging_enabled = false }

      it "does not return any tags" do
        expect(subject.search("book", %w[category tag]).map(&:text)).to eq(["The Book Club"])
      end
    end

    context "when no term is provided (default results) triggered by a # with no characters in the UI" do
      fab!(:category2) do
        Fabricate(:category, name: "Book Zone", slug: "book-zone", topic_count: 546)
      end
      fab!(:category3) do
        Fabricate(:category, name: "Book Dome", slug: "book-dome", topic_count: 987)
      end
      fab!(:category4) { Fabricate(:category, name: "Bookworld", slug: "book", topic_count: 56) }
      fab!(:category5) { Fabricate(:category, name: "Media", slug: "media", topic_count: 446) }
      fab!(:tag2) { Fabricate(:tag, name: "mid-books", topic_count: 33) }
      fab!(:tag3) { Fabricate(:tag, name: "terrible-books", topic_count: 2) }
      fab!(:tag4) { Fabricate(:tag, name: "book", topic_count: 1) }

      it "returns the 'most polular' categories and tags (based on topic_count) that the user can access" do
        category1.update!(read_restricted: true)
        Fabricate(:tag_group, permissions: { "staff" => 1 }, tag_names: ["terrible-books"])

        expect(subject.search(nil, %w[category tag]).map(&:text)).to eq(
          [
            "Book Dome",
            "Book Zone",
            "Media",
            "Bookworld",
            Category.find(SiteSetting.uncategorized_category_id).name,
            "mid-books",
            "great-books",
            "book",
          ],
        )
      end
    end
  end

  describe "#lookup_old" do
    fab!(:tag2) { Fabricate(:tag, name: "fiction-books") }

    it "returns categories and tags in a hash format with the slug and url" do
      result = subject.lookup_old(%w[the-book-club great-books fiction-books])
      expect(result[:categories]).to eq({ "the-book-club" => "/c/the-book-club/#{category1.id}" })
      expect(result[:tags]).to eq(
        {
          "fiction-books" => "http://test.localhost/tag/fiction-books",
          "great-books" => "http://test.localhost/tag/great-books",
        },
      )
    end

    it "does not include categories the user cannot access" do
      category1.update!(read_restricted: true)
      result = subject.lookup_old(%w[the-book-club great-books fiction-books])
      expect(result[:categories]).to eq({})
    end

    it "does not include tags the user cannot access" do
      Fabricate(:tag_group, permissions: { "staff" => 1 }, tag_names: ["great-books"])
      result = subject.lookup_old(%w[the-book-club great-books fiction-books])
      expect(result[:tags]).to eq({ "fiction-books" => "http://test.localhost/tag/fiction-books" })
    end

    it "handles tags which have the ::tag suffix" do
      result = subject.lookup_old(%w[the-book-club great-books::tag fiction-books])
      expect(result[:tags]).to eq(
        {
          "fiction-books" => "http://test.localhost/tag/fiction-books",
          "great-books" => "http://test.localhost/tag/great-books",
        },
      )
    end

    context "when not tagging_enabled" do
      before { SiteSetting.tagging_enabled = false }

      it "does not return tags" do
        result = subject.lookup_old(%w[the-book-club great-books fiction-books])
        expect(result[:categories]).to eq({ "the-book-club" => "/c/the-book-club/#{category1.id}" })
        expect(result[:tags]).to eq({})
      end
    end
  end

  describe "#lookup" do
    fab!(:tag2) { Fabricate(:tag, name: "fiction-books") }

    it "returns category and tag in a hash format with the slug and url" do
      result = subject.lookup(%w[the-book-club great-books fiction-books], %w[category tag])
      expect(result[:category].map(&:slug)).to eq(["the-book-club"])
      expect(result[:category].map(&:relative_url)).to eq(["/c/the-book-club/#{category1.id}"])
      expect(result[:tag].map(&:slug)).to eq(%w[fiction-books great-books])
      expect(result[:tag].map(&:relative_url)).to eq(%w[/tag/fiction-books /tag/great-books])
    end

    it "does not include category the user cannot access" do
      category1.update!(read_restricted: true)
      result = subject.lookup(%w[the-book-club great-books fiction-books], %w[category tag])
      expect(result[:category]).to eq([])
    end

    it "does not include tag the user cannot access" do
      Fabricate(:tag_group, permissions: { "staff" => 1 }, tag_names: ["great-books"])
      result = subject.lookup(%w[the-book-club great-books fiction-books], %w[category tag])
      expect(result[:tag].map(&:slug)).to eq(%w[fiction-books])
      expect(result[:tag].map(&:relative_url)).to eq(["/tag/fiction-books"])
    end

    it "handles type suffixes for slugs" do
      result =
        subject.lookup(%w[the-book-club::category great-books::tag fiction-books], %w[category tag])
      expect(result[:category].map(&:slug)).to eq(["the-book-club"])
      expect(result[:category].map(&:relative_url)).to eq(["/c/the-book-club/#{category1.id}"])
      expect(result[:tag].map(&:slug)).to eq(%w[fiction-books great-books])
      expect(result[:tag].map(&:relative_url)).to eq(%w[/tag/fiction-books /tag/great-books])
    end

    it "handles parent:child category lookups" do
      parent_category = Fabricate(:category, name: "Media", slug: "media")
      category1.update!(parent_category: parent_category)
      result = subject.lookup(%w[media:the-book-club], %w[category tag])
      expect(result[:category].map(&:slug)).to eq(["the-book-club"])
      expect(result[:category].map(&:ref)).to eq(["media:the-book-club"])
      expect(result[:category].map(&:relative_url)).to eq(
        ["/c/media/the-book-club/#{category1.id}"],
      )
      category1.update!(parent_category: nil)
    end

    it "does not return the category if the parent does not match the child" do
      parent_category = Fabricate(:category, name: "Media", slug: "media")
      category1.update!(parent_category: parent_category)
      result = subject.lookup(%w[bad-parent:the-book-club], %w[category tag])
      expect(result[:category]).to be_empty
    end

    it "for slugs without a type suffix it falls back in type order until a result is found or types are exhausted" do
      result = subject.lookup(%w[the-book-club great-books fiction-books], %w[category tag])
      expect(result[:category].map(&:slug)).to eq(["the-book-club"])
      expect(result[:category].map(&:relative_url)).to eq(["/c/the-book-club/#{category1.id}"])
      expect(result[:tag].map(&:slug)).to eq(%w[fiction-books great-books])
      expect(result[:tag].map(&:relative_url)).to eq(%w[/tag/fiction-books /tag/great-books])

      category2 = Fabricate(:category, name: "Great Books", slug: "great-books")
      result = subject.lookup(%w[the-book-club great-books fiction-books], %w[category tag])
      expect(result[:category].map(&:slug)).to eq(%w[great-books the-book-club])
      expect(result[:category].map(&:relative_url)).to eq(
        ["/c/great-books/#{category2.id}", "/c/the-book-club/#{category1.id}"],
      )
      expect(result[:tag].map(&:slug)).to eq(%w[fiction-books])
      expect(result[:tag].map(&:relative_url)).to eq(%w[/tag/fiction-books])

      category1.destroy!
      Fabricate(:tag, name: "the-book-club")
      result = subject.lookup(%w[the-book-club great-books fiction-books], %w[category tag])
      expect(result[:category].map(&:slug)).to eq(["great-books"])
      expect(result[:category].map(&:relative_url)).to eq(["/c/great-books/#{category2.id}"])
      expect(result[:tag].map(&:slug)).to eq(%w[fiction-books the-book-club])
      expect(result[:tag].map(&:relative_url)).to eq(%w[/tag/fiction-books /tag/the-book-club])

      result = subject.lookup(%w[the-book-club great-books fiction-books], %w[tag category])
      expect(result[:category]).to eq([])
      expect(result[:tag].map(&:slug)).to eq(%w[fiction-books great-books the-book-club])
      expect(result[:tag].map(&:relative_url)).to eq(
        %w[/tag/fiction-books /tag/great-books /tag/the-book-club],
      )
    end

    it "includes other data sources" do
      Fabricate(:bookmark, user: user, name: "read review of this fantasy book")
      Fabricate(:bookmark, user: user, name: "coolrock")
      guardian.user.reload

      DiscoursePluginRegistry.register_hashtag_autocomplete_data_source(
        FakeBookmarkHashtagDataSource,
        stub(enabled?: true),
      )

      result = subject.lookup(["coolrock"], %w[category tag bookmark])
      expect(result[:bookmark].map(&:slug)).to eq(["coolrock"])
    end

    it "handles type suffix lookups where there is another type with a conflicting slug that the user cannot access" do
      category1.update!(read_restricted: true)
      Fabricate(:tag, name: "the-book-club")
      result = subject.lookup(%w[the-book-club::tag the-book-club], %w[category tag])
      expect(result[:category].map(&:ref)).to eq([])
      expect(result[:tag].map(&:ref)).to eq(["the-book-club::tag"])
    end

    context "when not tagging_enabled" do
      before { SiteSetting.tagging_enabled = false }

      it "does not return tag" do
        result = subject.lookup(%w[the-book-club great-books fiction-books], %w[category tag])
        expect(result[:category].map(&:slug)).to eq(["the-book-club"])
        expect(result[:category].map(&:relative_url)).to eq(["/c/the-book-club/#{category1.id}"])
        expect(result[:tag]).to eq([])
      end
    end
  end
end
