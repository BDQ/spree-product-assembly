# Uncomment this if you reference any of your controllers in activate
# require_dependency 'application'

class ProductAssemblyExtension < Spree::Extension
  version "1.0"
  description "Describe your extension here"
  url "http://yourwebsite.com/product_assembly"

  # Please use product_assembly/config/routes.rb instead for extension routes.

  def self.require_gems(config)
    #config.gem 'composite_primary_keys', :lib => false
  end

  def activate

    Product.class_eval do

      has_and_belongs_to_many  :assemblies, :class_name => "Product",
            :join_table => "assemblies_parts",
            :foreign_key => "part_id", :association_foreign_key => "assembly_id"

      has_and_belongs_to_many  :parts, :class_name => "Variant",
            :join_table => "assemblies_parts",
            :foreign_key => "assembly_id", :association_foreign_key => "part_id"


      named_scope :individual_saled, {
        :conditions => ["products.individual_sale = ?", true]
      }

      named_scope :active, lambda { |*args|
        not_deleted.individual_saled.available(args.first).scope(:find)
      }


      alias_method :orig_on_hand, :on_hand
      # returns the number of inventory units "on_hand" for this product
      def on_hand
        if self.assembly? && Spree::Config[:track_inventory_levels]
          parts.map{|v| v.on_hand / self.count_of(v) }.min
        else
          self.orig_on_hand
        end
      end

      alias_method :orig_on_hand=, :on_hand=
      def on_hand=(new_level)
        self.orig_on_hand=(new_level) unless self.assembly?
      end

      alias_method :orig_has_stock?, :has_stock?
      def has_stock?
        if self.assembly? && Spree::Config[:track_inventory_levels]
          !parts.detect{|v| self.count_of(v) > v.on_hand}
        else
          self.orig_has_stock?
        end
      end

      def add_part(variant, count = 1)
        ap = AssembliesPart.get(self.id, variant.id)
        unless ap.nil?
          ap.count += count
          ap.save
        else
          self.parts << variant
          set_part_count(variant, count) if count > 1
        end
      end

      def remove_part(variant)
        ap = AssembliesPart.get(self.id, variant.id)
        unless ap.nil?
          ap.count -= 1
          if ap.count > 0
            ap.save
          else
            ap.destroy
          end
        end
      end

      def set_part_count(variant, count)
        ap = AssembliesPart.get(self.id, variant.id)
        unless ap.nil?
          if count > 0
            ap.count = count
            ap.save
          else
            ap.destroy
          end
        end
      end

      def assembly?
        parts.present?
      end

      def part?
        assemblies.present?
      end

      def count_of(variant)
        ap = AssembliesPart.get(self.id, variant.id)
        ap ? ap.count : 0
      end

    end

    InventoryUnit.class_eval do
      def self.sell_units(order)
        # we should not already have inventory associated with the order at this point but we should clear to be safe (#1394)
        order.inventory_units.destroy_all

        out_of_stock_items = []
        order.line_items.each do |line_item|
          variant = line_item.variant
          quantity = line_item.quantity
          product = variant.product

          if product.assembly?
            product.parts.each do |v|
              out_of_stock_items += create_units(order, v, quantity * product.count_of(v))
            end
          else
            out_of_stock_items += create_units(order, variant, quantity)
          end
        end
        out_of_stock_items.flatten
      end

    end

  end
end
