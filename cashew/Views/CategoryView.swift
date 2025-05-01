import SwiftUI

struct CategoryView: View {
    @EnvironmentObject var dataManager: DataManager
    @State private var showingAddCategorySheet = false
    @State private var editingCategory: Category? = nil
    @State private var showAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    
    var body: some View {
        NavigationView {
            List {
                ForEach(dataManager.categories) { category in
                    CategoryRow(category: category)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            editingCategory = category
                        }
                }
                .onDelete { indexSet in
                    handleDelete(at: indexSet)
                }
            }
            .listStyle(InsetGroupedListStyle())
            .navigationTitle("Categories")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingAddCategorySheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddCategorySheet) {
                AddCategoryView(isPresented: $showingAddCategorySheet)
            }
            .sheet(item: $editingCategory) { category in
                EditCategoryView(isPresented: Binding<Bool>(
                    get: { editingCategory != nil },
                    set: { if !$0 { editingCategory = nil } }
                ), category: category)
            }
            .alert(isPresented: $showAlert) {
                Alert(title: Text(alertTitle), 
                      message: Text(alertMessage), 
                      dismissButton: .default(Text("OK")))
            }
        }
    }
    
    private func handleDelete(at indexSet: IndexSet) {
        for index in indexSet {
            let category = dataManager.categories[index]
            
            // Check if it's "Other" category - prevent deletion
            if category.name == "Other" {
                alertTitle = "Cannot Delete"
                alertMessage = "The 'Other' category cannot be deleted."
                showAlert = true
                return
            }
            
            // Check if it's the last category
            if dataManager.categories.count <= 1 {
                alertTitle = "Cannot Delete"
                alertMessage = "You must have at least one category."
                showAlert = true
                return
            }
            
            // Delete the category
            dataManager.deleteCategory(id: category.id)
        }
    }
}

struct CategoryRow: View {
    let category: Category
    
    var body: some View {
        HStack {
            Image(systemName: category.icon)
                .foregroundColor(category.color)
                .font(.system(size: 24))
                .frame(width: 32, height: 32)
                .background(category.color.opacity(0.1))
                .cornerRadius(8)
            
            Text(category.name)
                .font(.headline)
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .foregroundColor(Color.gray.opacity(0.5))
                .font(.caption)
        }
        .padding(.vertical, 8)
    }
}

struct AddCategoryView: View {
    @EnvironmentObject var dataManager: DataManager
    @Binding var isPresented: Bool
    
    @State private var categoryName = ""
    @State private var selectedIcon = "tag.fill"
    @State private var selectedColor = Color.blue
    
    // Available icons
    let availableIcons = [
        "tag.fill", "cart.fill", "fork.knife", "car.fill", "gamecontroller.fill", 
        "bolt.fill", "bag.fill", "heart.fill", "dollarsign.circle.fill", "house.fill", 
        "graduationcap.fill", "briefcase.fill", "globe.americas.fill", "gift.fill", 
        "suitcase.fill", "figure.walk", "airplane", "tram.fill", "waveform.path"
    ]
    
    // Available colors
    let availableColors: [Color] = [
        .blue, .red, .green, .orange, .purple, .yellow, .pink, .gray
    ]
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Category Details")) {
                    TextField("Category Name", text: $categoryName)
                }
                
                Section(header: Text("Icon")) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 15) {
                        ForEach(availableIcons, id: \.self) { icon in
                            Image(systemName: icon)
                                .font(.system(size: 24))
                                .foregroundColor(selectedIcon == icon ? selectedColor : .gray)
                                .frame(width: 44, height: 44)
                                .background(selectedIcon == icon ? selectedColor.opacity(0.1) : Color.clear)
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(selectedIcon == icon ? selectedColor : Color.clear, lineWidth: 2)
                                )
                                .onTapGesture {
                                    selectedIcon = icon
                                }
                        }
                    }
                    .padding(.vertical, 5)
                }
                
                Section(header: Text("Color")) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 15) {
                        ForEach(availableColors, id: \.self) { color in
                            Circle()
                                .fill(color)
                                .frame(width: 44, height: 44)
                                .overlay(
                                    Circle()
                                        .stroke(Color.white, lineWidth: 2)
                                        .padding(2)
                                )
                                .overlay(
                                    Circle()
                                        .stroke(selectedColor == color ? Color.black : Color.clear, lineWidth: 2)
                                )
                                .onTapGesture {
                                    selectedColor = color
                                }
                        }
                    }
                    .padding(.vertical, 5)
                }
            }
            .navigationTitle("Add Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveCategory()
                        isPresented = false
                    }
                    .disabled(categoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
    
    private func saveCategory() {
        let trimmedName = categoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty {
            dataManager.addCategory(name: trimmedName, icon: selectedIcon, color: selectedColor)
        }
    }
}

struct EditCategoryView: View {
    @EnvironmentObject var dataManager: DataManager
    @Binding var isPresented: Bool
    let category: Category
    
    @State private var categoryName: String
    @State private var selectedIcon: String
    @State private var selectedColor: Color
    @State private var showDeleteAlert = false
    
    // Available icons
    let availableIcons = [
        "tag.fill", "cart.fill", "fork.knife", "car.fill", "gamecontroller.fill", 
        "bolt.fill", "bag.fill", "heart.fill", "dollarsign.circle.fill", "house.fill", 
        "graduationcap.fill", "briefcase.fill", "globe.americas.fill", "gift.fill", 
        "suitcase.fill", "figure.walk", "airplane", "tram.fill", "waveform.path"
    ]
    
    // Available colors
    let availableColors: [Color] = [
        .blue, .red, .green, .orange, .purple, .yellow, .pink, .gray
    ]
    
    // Initialize state with the category values
    init(isPresented: Binding<Bool>, category: Category) {
        self._isPresented = isPresented
        self.category = category
        self._categoryName = State(initialValue: category.name)
        self._selectedIcon = State(initialValue: category.icon)
        self._selectedColor = State(initialValue: category.color)
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Category Details")) {
                    TextField("Category Name", text: $categoryName)
                }
                
                Section(header: Text("Icon")) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 15) {
                        ForEach(availableIcons, id: \.self) { icon in
                            Image(systemName: icon)
                                .font(.system(size: 24))
                                .foregroundColor(selectedIcon == icon ? selectedColor : .gray)
                                .frame(width: 44, height: 44)
                                .background(selectedIcon == icon ? selectedColor.opacity(0.1) : Color.clear)
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(selectedIcon == icon ? selectedColor : Color.clear, lineWidth: 2)
                                )
                                .onTapGesture {
                                    selectedIcon = icon
                                }
                        }
                    }
                    .padding(.vertical, 5)
                }
                
                Section(header: Text("Color")) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 15) {
                        ForEach(availableColors, id: \.self) { color in
                            Circle()
                                .fill(color)
                                .frame(width: 44, height: 44)
                                .overlay(
                                    Circle()
                                        .stroke(Color.white, lineWidth: 2)
                                        .padding(2)
                                )
                                .overlay(
                                    Circle()
                                        .stroke(selectedColor == color ? Color.black : Color.clear, lineWidth: 2)
                                )
                                .onTapGesture {
                                    selectedColor = color
                                }
                        }
                    }
                    .padding(.vertical, 5)
                }
                
                // Only show delete option if it's not the "Other" category
                if category.name != "Other" {
                    Section {
                        Button(action: {
                            showDeleteAlert = true
                        }) {
                            HStack {
                                Spacer()
                                Text("Delete Category")
                                    .foregroundColor(.red)
                                Spacer()
                            }
                        }
                    }
                }
            }
            .navigationTitle("Edit Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        updateCategory()
                        isPresented = false
                    }
                    .disabled(categoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .alert(isPresented: $showDeleteAlert) {
                Alert(
                    title: Text("Delete Category"),
                    message: Text("Are you sure you want to delete this category? All transactions in this category will be moved to 'Other'."),
                    primaryButton: .destructive(Text("Delete")) {
                        dataManager.deleteCategory(id: category.id)
                        isPresented = false
                    },
                    secondaryButton: .cancel()
                )
            }
        }
    }
    
    private func updateCategory() {
        let trimmedName = categoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty {
            dataManager.updateCategory(
                id: category.id,
                name: trimmedName,
                icon: selectedIcon,
                color: selectedColor
            )
            
            // Update any transactions using the old category name
            if trimmedName != category.name {
                for i in 0..<dataManager.financeTransactions.count {
                    if dataManager.financeTransactions[i].category == category.name {
                        dataManager.financeTransactions[i].category = trimmedName
                    }
                }
                dataManager.saveFinanceTransactions()
            }
        }
    }
}

#Preview {
    CategoryView()
        .environmentObject(DataManager())
}